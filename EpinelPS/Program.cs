using EpinelPS.Data;
using EpinelPS.Database;
using EpinelPS.Interfaces;
using EpinelPS.LobbyServer;
using EpinelPS.Networking;
using EpinelPS.Services;
using EpinelPS.Utils;
using EpinelPS.LobbyServer.Stage;
using log4net.Config;
using Microsoft.AspNetCore.Server.Kestrel.Core;
using Microsoft.AspNetCore.Server.Kestrel.Https;
using Microsoft.EntityFrameworkCore;
using Microsoft.Extensions.DependencyInjection;
using System.Net;
using System.Reflection;
using System.Security.Cryptography.X509Certificates;
using System.Text;

namespace EpinelPS;

internal class Program
{
    static async Task Main(string[] args)
    {
        try
        {
            XmlConfigurator.Configure(new FileInfo("log4net.config"));
            Console.WriteLine($"EpinelPS v{Assembly.GetExecutingAssembly().GetName().Version} - https://github.com/EpinelPS/EpinelPS/");
            Console.WriteLine("This software is licensed under the AGPL-3.0 License");
            Console.WriteLine("Targeting game version " + GameConfig.Root.TargetVersion);
            Console.WriteLine("Git commit " + GitUpdateCheck.GitCommit);
            if (!File.Exists(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gamecommon.json")))
            {
                Console.WriteLine("gamecommon.json does not exist, please go to our discord server for assistance");
                return;
            }
            
            try
            {
                if (args.Length == 0 || args[0] != "--headless")
                    await GitUpdateCheck.CheckForUpdates();
            }
            catch(Exception ex)
            {
                Console.WriteLine("Failed to check for updates: " + ex.Message);
            }

            await GameData.CreateAsync();
            foreach (var user in JsonDb.Instance.Users)
            {
                if (user.LastNormalStageCleared >= 6000002)
                {
                    ClearStage.EnsureDefaultCharacters(user);
                }
                ClearStage.ReconcileMainQuests(user, logToConsole: false);
                MessengerMessageCreator.CreateAllEligibleOpeners(user, logToConsole: false);
            }

            Console.WriteLine("Initializing database");
            JsonDb.Save();

            Logging.WriteLine("Register handlers");
            LobbyHandler.Init();

            Logging.WriteLine("Starting ASP.NET core on ports 80 and 443");
            WebApplicationBuilder builder = WebApplication.CreateBuilder(args);

            // Configure HTTPS
            // Local build patch: .NET 10's PKCS12 loader rejects the existing site.pfx
            // ("the specified network password is not correct") even though the file is a
            // valid, password-less, AES-256/SHA-256 PKCS#12 (OpenSSL reads it fine).
            // Prefer loading the certificate from PEM instead — that path skips PKCS#12
            // parsing entirely — and fall back to the PFX if the PEM pair is absent.
            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string pemCertPath = Path.Combine(baseDir, "server.crt");
            string pemKeyPath = Path.Combine(baseDir, "server.key");
            string pemCaPath = Path.Combine(baseDir, "ca.crt");

            X509Certificate2 serverCertificate;
            X509Certificate2Collection? serverChain = null;
            // Local build patch: parsing the PKCS#12 blob fails inside this application
            // ("the specified network password is not correct" / "Access is denied") even though
            // the very same file loads fine from a standalone .NET 10 process and from OpenSSL.
            // The certificate is therefore imported into the CurrentUser\My store by
            // tools/install-cert.ps1 and loaded from there, which avoids PKCS#12 parsing and
            // gives Schannel a persistent private key.
            const string ServerCertThumbprint = "B8C27EB20A0F128BCA489F58A725B445E9CFCEAC";
            X509Certificate2? fromStore = null;
            try
            {
                using X509Store store = new(StoreName.My, StoreLocation.CurrentUser);
                store.Open(OpenFlags.ReadOnly | OpenFlags.OpenExistingOnly);
                X509Certificate2Collection matches =
                    store.Certificates.Find(X509FindType.FindByThumbprint, ServerCertThumbprint, false);
                if (matches.Count > 0)
                {
                    fromStore = matches[0];
                    Console.WriteLine($"[CERT] loaded from CurrentUser\\My store: {fromStore.Thumbprint}");
                }
                else
                {
                    Console.WriteLine($"[CERT] thumbprint {ServerCertThumbprint} not found in CurrentUser\\My");
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[CERT] certificate store lookup failed: {ex.GetType().Name}: {ex.Message}");
            }

            if (fromStore is not null)
            {
                serverCertificate = fromStore;
            }
            else if (File.Exists(pemCertPath) && File.Exists(pemKeyPath))
            {
                byte[] crtBytes = File.ReadAllBytes(pemCertPath);
                byte[] keyBytes = File.ReadAllBytes(pemKeyPath);
                Console.WriteLine($"[CERT] crt {pemCertPath} = {crtBytes.Length} bytes");
                Console.WriteLine($"[CERT] key {pemKeyPath} = {keyBytes.Length} bytes");
                string certPem = System.Text.Encoding.ASCII.GetString(crtBytes);
                string keyPem = System.Text.Encoding.ASCII.GetString(keyBytes);
                serverCertificate = X509Certificate2.CreateFromPem(certPem, keyPem);
                Console.WriteLine($"[CERT] loaded PEM {pemCertPath}");
                if (File.Exists(pemCaPath))
                {
                    serverChain = [X509Certificate2.CreateFromPem(File.ReadAllText(pemCaPath))];
                    Console.WriteLine($"[CERT] loaded CA {pemCaPath}");
                }
            }
            else
            {
                string pfxPath = Path.Combine(baseDir, "site.pfx");
                byte[] pfxBytes = File.ReadAllBytes(pfxPath);
                Console.WriteLine($"[CERT] loaded PFX {pfxPath} ({pfxBytes.Length} bytes)");
                serverCertificate = X509CertificateLoader.LoadPkcs12(pfxBytes, null);
            }
            Console.WriteLine($"[CERT] subject={serverCertificate.Subject}");
            Console.WriteLine($"[CERT] thumbprint={serverCertificate.Thumbprint}");
            Console.WriteLine($"[CERT] hasPrivateKey={serverCertificate.HasPrivateKey}");

            HttpsConnectionAdapterOptions httpsConnectionAdapterOptions = new()
            {
                SslProtocols = System.Security.Authentication.SslProtocols.Tls12,
                ClientCertificateMode = ClientCertificateMode.AllowCertificate,
                ServerCertificate = serverCertificate
            };
            if (serverChain is not null)
                httpsConnectionAdapterOptions.ServerCertificateChain = serverChain;

            builder.WebHost.ConfigureKestrel(serverOptions =>
            {
                serverOptions.Listen(IPAddress.Any, 443,
                    listenOptions =>
                    {
                        listenOptions.Protocols = HttpProtocols.Http1AndHttp2AndHttp3;
                        listenOptions.UseHttps(httpsConnectionAdapterOptions);
                    });
                serverOptions.Listen(IPAddress.Loopback, 80,
               listenOptions =>
               {
                   listenOptions.Protocols = HttpProtocols.Http1;
               });
                // TODO
                serverOptions.AllowSynchronousIO = true;
            });


            // Add services to the container.
            string connectionString = builder.Configuration.GetConnectionString("EpinelPSConnection").Replace("(startupDirectory)", AppDomain.CurrentDomain.BaseDirectory);
            string connectionType = builder.Configuration.GetConnectionString("EpinelPSConnectionType").ToLower();
            GameContext.InitializeOptions(connectionString, connectionType);
            builder.Services.AddHttpContextAccessor();
            builder.Services.AddScoped<IUserService, UserService>();
            builder.Services.AddSingleton<MessengerAdminService>();
            builder.Services.AddDbContext<GameContext>(options =>
            {
                switch (connectionType?.ToLowerInvariant())
                {
                    case "sql":
                        options.UseSqlServer(connectionString);
                        break;

                    case "mysql":
                        options.UseMySQL(connectionString);
                        break;

                    case "npgsql":
                        options.UseNpgsql(connectionString);
                        break;

                    default:
                        options.UseSqlite(connectionString);
                        break;
                }
            });
            builder.Services.AddControllersWithViews(options =>
            {
                options.AllowEmptyInputInBodyModelBinding = true;
                options.OutputFormatters.Insert(0, new ProtobufOutputFormatter());
            });
            // Learn more about configuring Swagger/OpenAPI at https://aka.ms/aspnetcore/swashbuckle
            builder.Services.AddEndpointsApiExplorer();
            builder.Services.AddRouting();
            builder.Services.AddHttpClient();

            builder.Logging.ClearProviders();
            builder.Logging.AddColorConsoleLogger(configuration =>
            {
                // Replace warning value from appsettings.json of "Cyan"
                configuration.LogLevelToColorMap[LogLevel.Warning] = ConsoleColor.Yellow;
                // Replace warning value from appsettings.json of "Red"
                configuration.LogLevelToColorMap[LogLevel.Error] = ConsoleColor.DarkRed;
            });


            WebApplication app = builder.Build();
            CreateDbIfNotExists(app);

            // Keep a startup scope alive for legacy code paths that use
            // GameContext.Instance (e.g. User.AddTrigger). GameContext is registered
            // as scoped, so it cannot be resolved directly from the root provider.
            // The scope is disposed automatically after app.Run() returns.
            using IServiceScope gameContextScope = app.Services.CreateScope();
            GameContext.SetInstance(gameContextScope.ServiceProvider.GetRequiredService<GameContext>());

            app.UseDefaultFiles();
            app.UseStaticFiles();
            app.UseMiddleware<EncryptionMiddleware>();


            // app.UseHttpsRedirection();

            // Diagnostic request logger (local build patch): records host + path + status
            // for every incoming request so launcher/client connectivity issues are visible.
            app.Use(async (ctx, next) =>
            {
                var sw = System.Diagnostics.Stopwatch.StartNew();
                await next();
                Console.WriteLine($"[REQ] {ctx.Request.Method} {ctx.Request.Scheme}://{ctx.Request.Host}{ctx.Request.Path}{ctx.Request.QueryString} -> {ctx.Response.StatusCode} ({sw.ElapsedMilliseconds}ms)");
            });

            // Local build patch: the launcher's downloader (tinyget) performs a telemetry call
            // (https://na.fleetlogd.com/fleet.repo.game.ReportGather/GuestReport) before the
            // "Catalogue resource path upgrade" step. ServerSelector blackholes that host, so the
            // call never succeeds, the retry strategies are exhausted and the launcher shows
            // "系统错误". Answer such telemetry calls with a success envelope so they stop failing.
            app.Use(async (ctx, next) =>
            {
                string path = ctx.Request.Path.Value ?? "";
                string host = ctx.Request.Host.Host ?? "";
                bool isTelemetry =
                    path.Contains("ReportGather", StringComparison.OrdinalIgnoreCase) ||
                    (host.Contains("fleetlogd", StringComparison.OrdinalIgnoreCase) &&
                     path.Contains("Report", StringComparison.OrdinalIgnoreCase));

                if (isTelemetry)
                {
                    ctx.Response.StatusCode = 200;
                    ctx.Response.ContentType = "application/json";
                    await ctx.Response.WriteAsync("{\"result\":{\"error_code\":0,\"error_message\":\"COMM_SUCC\"}}");
                    return;
                }

                await next();
            });

            app.UseAuthorization();
            //app.UseHttpsRedirection();
            app.UseRouting();
            app.MapControllerRoute(
       name: "default",
       pattern: "/admin/{controller=Admin}/{action=Dashboard}/{id?}");

            app.MapControllers();

            app.MapGet("/prdenv/{**all}", AssetDownloadUtil.HandleReq);
            app.MapGet("/PC/{**all}", AssetDownloadUtil.HandleReq);
            app.MapGet("/media/{**all}", AssetDownloadUtil.HandleReq);
            app.MapPost("/rqd/sync", HandleRqd);

            // NOTE: pub prefixes shows public (production server), local is local server (does not have any effect), dev is development server, etc.
            // It does not have any effect, except for the publisher server, which adds a watermark?

            app.MapGet("/route/{**all}", () => @"{
          ""Config"": [
            {
              ""VersionRange"": {
                ""From"": ""{GameMinVer}"",
                ""To"": ""{GameMaxVer}"",
                ""PackageName"": ""com.proximabeta.nikke""
              },
              ""Route"": [
                {
                  ""WorldId"": 81,
                  ""Name"": ""pub:live-jp"",
                  ""Url"": ""https://jp-lobby.nikke-kr.com/"",
                  ""Description"": ""JAPAN"",
                  ""Tags"": []
                },
                {
                  ""WorldId"": 82,
                  ""Name"": ""pub:live-na"",
                  ""Url"": ""https://us-lobby.nikke-kr.com/"",
                  ""Description"": ""NA"",
                  ""Tags"": []
                },
                {
                  ""WorldId"": 83,
                  ""Name"": ""pub:live-kr"",
                  ""Url"": ""https://kr-lobby.nikke-kr.com/"",
                  ""Description"": ""KOREA"",
                  ""Tags"": []
                },
                {
                  ""WorldId"": 84,
                  ""Name"": ""pub:live-global"",
                  ""Url"": ""https://global-lobby.nikke-kr.com/"",
                  ""Description"": ""GLOBAL"",
                  ""Tags"": []
                },
                {
                  ""WorldId"": 85,
                  ""Name"": ""pub:live-sea"",
                  ""Url"": ""https://sea-lobby.nikke-kr.com/"",
                  ""Description"": ""SEA"",
                  ""Tags"": []
                }
              ]
            },
            {
              ""VersionRange"": {
                ""From"": ""{GameMinVer}"",
                ""To"": ""{GameMaxVer}"",
                ""PackageName"": ""com.gamamobi.nikke""
              },
              ""Route"": [
                {
                  ""WorldId"": 91,
                  ""Name"": ""pub:live-hmt"",
                  ""Url"": ""https://hmt-lobby.nikke-kr.com/"",
                  ""Description"": ""HMT"",
                  ""Tags"": []
                }
              ]
            }
          ]
        }".Replace("{GameMinVer}", GameConfig.Root.GameMinVer).Replace("{GameMaxVer}", GameConfig.Root.GameMaxVer));

            app.MapGet("/", () =>
            {
                return $"EpinelPS v{Assembly.GetExecutingAssembly().GetName().Version} - https://github.com/EpinelPS/EpinelPS/";
            });

            new Thread(Commands.Services.CliLoop.Start).Start();
            app.Run();
        }
        catch (Exception ex) when (ex is not HostAbortedException && ex.Source != "Microsoft.EntityFrameworkCore.Design") // see https://github.com/dotnet/efcore/issues/29923
        {
            Console.WriteLine("Fatal error:");
            Console.WriteLine(ex.ToString());
            Console.WriteLine("Press any key to exit");
            Console.ReadKey();
        }
    }

    private static void CreateDbIfNotExists(IHost host)
    {
        using (var scope = host.Services.CreateScope())
        {
            var services = scope.ServiceProvider;
            try
            {
                var context = services.GetRequiredService<GameContext>();
                DbInitializer.Initialize(context);
            }
            catch (Exception ex)
            {
                var logger = services.GetRequiredService<ILogger<Program>>();
                logger.LogError(ex, "An error occurred creating the DB.");
            }
        }
    }

    private static void HandleRqd(HttpContext context)
    {

    }

    private static readonly string LauncherEndpoint = Encoding.UTF8.GetString(Convert.FromBase64String("L25pa2tlX2xhdW5jaGVy"));

    public static string GetCachePathForPath(string path)
    {
        return AppDomain.CurrentDomain.BaseDirectory + "cache/" + path;
    }

}
