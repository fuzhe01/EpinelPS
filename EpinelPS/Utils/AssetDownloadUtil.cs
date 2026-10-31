using DnsClient;
using System.Net;

namespace EpinelPS.Utils;

public class AssetDownloadUtil
{
    // NOTE (local build patch): the default HttpClient timeout of 100 s aborts any
    // CDN transfer larger than ~14 MB on a slow (~130 KB/s) link, which breaks
    // asset downloads and therefore the game client. Use a long timeout instead.
    public static readonly HttpClient AssetDownloader = new(new HttpClientHandler() { AutomaticDecompression = DecompressionMethods.All })
    {
        Timeout = TimeSpan.FromMinutes(30)
    };

    private static string? CloudIp;
    public static async Task<string?> DownloadOrGetFileAsync(string url, CancellationToken cancellationToken)
    {
        string rawUrl = url.Replace("https://cloud.nikke-kr.com/", "");
        string targetFile = Program.GetCachePathForPath(rawUrl);
        string? targetDir = Path.GetDirectoryName(targetFile);
        if (targetDir == null)
        {
            Console.WriteLine($"ERROR: Directory name cannot be null for request " + url + ", file path is " + targetFile);
            return null;
        }
        Directory.CreateDirectory(targetDir);

        Logging.WriteLine("Game is requesting " + targetFile);
        if (!File.Exists(targetFile))
        {
            CloudIp ??= await GetIpAsync("cloud.nikke-kr.com");

            Uri requestUri = new("https://" + CloudIp + "/" + rawUrl);
            using HttpRequestMessage request = new(HttpMethod.Get, requestUri);
            request.Headers.TryAddWithoutValidation("host", "cloud.nikke-kr.com");
            using HttpResponseMessage response = await AssetDownloader.SendAsync(request, cancellationToken);
            if (response.StatusCode == HttpStatusCode.OK)
            {
                if (!File.Exists(targetFile))
                {
                    using FileStream fss = new(targetFile, FileMode.CreateNew);
                    await response.Content.CopyToAsync(fss, cancellationToken);

                    fss.Close();
                }
            }
            else
            {
                Console.WriteLine("Failed to download " + url + " with status code " + response.StatusCode);
                return null;
            }
        }

        return targetFile;
    }

    public static async Task HandleReq(HttpContext context, string all)
    {
        string? targetFile = await DownloadOrGetFileAsync(context.Request.Path.Value ?? "", CancellationToken.None);

        if (targetFile != null)
        {
            string? contentType = null;
            if (targetFile.EndsWith("mp4"))
                contentType = "video/mp4";

            await Results.Stream(new FileStream(targetFile, FileMode.Open, FileAccess.Read, FileShare.Read), contentType: contentType, enableRangeProcessing: true).ExecuteAsync(context);
        }
        else
            context.Response.StatusCode = 404;
    }

    public static async Task<string> GetIpAsync(string query)
    {
        // Local build patch: prefer the OS resolver so hosts pins are honoured
        // (cloud.nikke-kr.com is regionally blackholed upstream -> black.nikke-kr.com
        // -> 0.0.0.1 for mainland clients, while hosts pins the real CloudFront IPs).
        // Fall back to a direct DNS query when the hosts entry points at localhost,
        // because ServerSelector redirects the lobby domains to 127.0.0.1.
        try
        {
            IPAddress[] resolved = Dns.GetHostAddresses(query);
            IPAddress? v4 = resolved.FirstOrDefault(a =>
                a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork);

            if (v4 != null && !IPAddress.IsLoopback(v4) &&
                !v4.Equals(IPAddress.Any) && !v4.Equals(IPAddress.None))
            {
                return v4.ToString();
            }
        }
        catch
        {
            // fall through to the direct DNS query below
        }

        LookupClient lookup = new();
        IDnsQueryResponse result = await lookup.QueryAsync(query, QueryType.A);

        DnsClient.Protocol.ARecord? record = result.Answers.ARecords().FirstOrDefault();
        IPAddress ip = record?.Address ?? throw new Exception($"Failed to find IP address of {query}, check your internet connection.");

        return ip.ToString();
    }
}
