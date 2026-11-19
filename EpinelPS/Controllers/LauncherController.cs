using EpinelPS.Database;
using Microsoft.AspNetCore.Mvc;
using System.Text;

namespace EpinelPS.Controllers;

[Route("/api/v1")]
[ApiController]
public class LauncherController(GameContext dbContext) : Controller
{
    private readonly GameContext _dbContext = dbContext;

    // 官方 AuthSvr 的真实地址。hosts 把 www.jupiterlauncher.com 指向 127.0.0.1，
    // 所以必须用真实 IP 直连 + 手动设置 Host 头，否则会转发给自己造成死循环。
    private static readonly string[] OfficialAuthHosts =
    {
        "50.18.48.216",
        "54.193.191.76",
    };

    [HttpPost]
    [Route("fleet.auth.game.AuthSvr/Login")]
    public async Task<string> LauncherLogin()
    {
        // 读原始请求体（启动器发什么就转发什么，避免格式被改写）
        string rawBody = string.Empty;
        try
        {
            Request.EnableBuffering();
            using var reader = new StreamReader(Request.Body, Encoding.UTF8, leaveOpen: true);
            rawBody = await reader.ReadToEndAsync();
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[LAUNCHER] read body failed: {ex.Message}");
        }

        Console.WriteLine($"[LAUNCHER] AuthSvr/Login body = {(rawBody.Length > 400 ? rawBody[..400] + "..." : rawBody)}");

        // ── 优先：转发到官方，拿真正的 LevelInfinite ticket ──
        // INTL SDK 会把这个 ticket 做 base64 解码后送到 gate，PASETO/uid 都不被接受。
        var forwarded = await TryForwardToOfficial(rawBody);
        if (forwarded is not null)
        {
            Console.WriteLine("[LAUNCHER] AuthSvr/Login -> forwarded to official OK");
            return forwarded;
        }

        // ── 回落：本地 PASETO（官方不可达时，至少让 /account/getuserinfo 链路可用）──
        Console.WriteLine("[LAUNCHER] official unreachable, falling back to local PASETO");

        string openid = string.Empty;
        string uid = string.Empty;
        string nickname = string.Empty;
        string token = string.Empty;

        try
        {
            // SQLite cannot ORDER BY a ulong column, so materialise first and sort in memory.
            var sdkUser = _dbContext.SdkUsers.ToList().OrderBy(u => u.ID).FirstOrDefault();
            if (sdkUser is not null)
            {
                uid = sdkUser.ID.ToString();
                openid = uid;
                nickname = sdkUser.PlayerName ?? string.Empty;

                var accessToken = AccountController.CreateLauncherTokenForUser(sdkUser.ID);
                token = accessToken.Token;
                Console.WriteLine($"[LAUNCHER] fallback -> uid={uid}, PASETO len={token.Length}");
            }
            else
            {
                Console.WriteLine("[LAUNCHER] fallback -> no account in SdkUsers");
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[LAUNCHER] fallback failed: {ex.GetType().Name}: {ex.Message}");
        }

        return @"{
    ""result"": {
        ""error_code"": 0,
        ""error_message"": ""COMM_SUCC""
    },
    ""channel"": 0,
    ""game_id"": ""29080"",
    ""openid"": """ + openid + @""",
    ""uid"": """ + uid + @""",
    ""biz_ticket"": """ + token + @""",
    ""expire_interval"": 86400,
    ""refresh_interval"": 604800,
    ""login_key"": """ + token + @""",
    ""login_ticket"": """ + token + @""",
    ""third_uid"": """ + uid + @""",
    ""user_name"": """ + nickname + @"""
}";
    }

    /// <summary>
    /// 把 AuthSvr/Login 转发到官方服务器。成功（error_code == 0 且有 biz_ticket）返回响应体，
    /// 否则返回 null 让调用方回落。
    /// </summary>
    private static async Task<string?> TryForwardToOfficial(string rawBody)
    {
        foreach (var host in OfficialAuthHosts)
        {
            try
            {
                // handler 必须每次新建：using 释放 HttpClient 时会连带 dispose handler，
                // 复用会在第二个 host 上抛 ObjectDisposedException。
                using var handler = new HttpClientHandler
                {
                    ServerCertificateCustomValidationCallback = (_, _, _, _) => true,
                };
                using var client = new HttpClient(handler) { Timeout = TimeSpan.FromSeconds(12) };
                using var req = new HttpRequestMessage(HttpMethod.Post,
                    $"https://{host}/api/v1/fleet.auth.game.AuthSvr/Login");
                req.Headers.Host = "www.jupiterlauncher.com";
                req.Content = new StringContent(
                    string.IsNullOrWhiteSpace(rawBody) ? "{}" : rawBody,
                    Encoding.UTF8, "application/json");

                using var resp = await client.SendAsync(req);
                string body = await resp.Content.ReadAsStringAsync();

                Console.WriteLine($"[LAUNCHER] official {host} -> {(int)resp.StatusCode} " +
                                  $"{(body.Length > 240 ? body[..240] + "..." : body)}");

                if ((int)resp.StatusCode == 200
                    && body.Contains("\"error_code\":0")
                    && body.Contains("biz_ticket"))
                {
                    return body;
                }
            }
            catch (Exception ex)
            {
                Console.WriteLine($"[LAUNCHER] official {host} failed: {ex.GetType().Name}: {ex.Message}");
            }
        }

        return null;
    }

    [HttpPost]
    [Route("fleet.repo.game.RepoSVC/GetRegion")]
    public string LauncherGetRegion()
    {
        return @"{
    ""result"": {
        ""error_code"": 0,
        ""error_message"": ""success""
    },
    ""region_info"": [
        {
            ""game_id"": ""16601"",
            ""region_id"": ""10001"",
            ""region_name_en_us"": ""Global"",
            ""region_name_i18n"": """",
            ""region_description_en_us"": ""Nikke Global Version"",
            ""region_description_i18n"": """",
            ""bind_branches"": """",
            ""meta_data"": """",
            ""sequence"": 0,
            ""status"": 2,
            ""branch_info"": [
                {
                    ""game_id"": ""16601"",
                    ""branch_id"": ""1"",
                    ""branch_name"": ""Official_release"",
                    ""branch_type"": 0,
                    ""description"": ""正式发布环境 release包""
                }
            ]
        }
    ]
}";
    }

    [HttpPost]
    [Route("fleet.repo.game.RepoSVC/GetGameLauncher")]
    // Local build patch: the real launcher requests this endpoint under "RepoMgr"
    // (fleet.repo.game.RepoMgr/GetGameLauncher), not "RepoSVC". Keeping only the RepoSVC
    // route left the launcher with a 404 and made its announcement dialog show
    // "系统错误". Both spellings are now served.
    [Route("fleet.repo.game.RepoMgr/GetGameLauncher")]
    public string LauncherGetLauncher()
    {
        return @"{
    ""result"": {
        ""error_code"": 0,
        ""error_message"": ""COMM_SUCC""
    },
    ""game_launcher_info"": [
        {
            ""id"": 27,
            ""execute_file"": ""NIKKE\\Game\\NIKKE.exe"",
            ""param"": """",
            ""description"": ""Nikke main process"",
            ""os"": ""any"",
            ""branch_id"": 0,
            ""status"": 1,
            ""param_type"": 1
        }
    ]
}";
    }

    [HttpPost]
    [Route("fleet.repo.game.RepoSVC/GetVersion")]
    public string LauncherGetVersion([FromBody] LauncherVersionRequest? body)
    {
        if (body == null)
        {
            return "{}";
        }

        return System.IO.File.ReadAllText(Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "gameversion.json"));
    }

    [HttpPost]
    // Local build patch: the launcher polls Payment/GetActivityStatus. The upstream server
    // never implemented it, so the call returned 404 and the launcher surfaced
    // "系统错误" (system error) in its announcement dialog. Answer with a successful
    // but empty activity list instead: there are no paid promotions on a private server.
    [Route("fleet.billing.game.Payment/GetActivityStatus")]
    public string LauncherGetActivityStatus()
    {
        return @"{
    ""result"": {
        ""error_code"": 0,
        ""error_message"": ""COMM_SUCC""
    },
    ""activity_status"": []
}";
    }

    public class LauncherVersionRequest
    {
        public int game_id { get; set; }
        public int branch_id { get; set; }
    }
}
