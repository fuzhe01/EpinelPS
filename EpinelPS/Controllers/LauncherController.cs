using EpinelPS.Database;
using Microsoft.AspNetCore.Mvc;

namespace EpinelPS.Controllers;

[Route("/api/v1")]
[ApiController]
public class LauncherController : Controller
{
    [HttpPost]
    [Route("fleet.auth.game.AuthSvr/Login")]
    public string LauncherLogin()
    {
        // Local build patch: upstream returned hardcoded empty credentials
        // (openid/uid/biz_ticket/login_ticket/login_key all ""). The launcher stores that and
        // hands an empty token to the game, which then fails with
        //   [SDK] INTL result failed. methodId 13101, retCode 1002
        //   "Login failed, please login from launcher again."
        // Return the real account so the game gets a usable token. On a private server the
        // first (or only) account is the local player.
        string openid = string.Empty;
        string uid = string.Empty;
        string nickname = string.Empty;

        try
        {
            var users = JsonDb.Instance.Users;
            if (users is { Count: > 0 })
            {
                var user = users[0];
                uid = user.ID.ToString();
                openid = uid;
                nickname = user.PlayerName ?? string.Empty;
            }
        }
        catch (Exception ex)
        {
            Console.WriteLine($"[LAUNCHER] failed to read local user: {ex.GetType().Name}: {ex.Message}");
        }

        Console.WriteLine($"[LAUNCHER] AuthSvr/Login -> uid={uid} openid={openid}");

        return @"{
    ""result"": {
        ""error_code"": 0,
        ""error_message"": ""COMM_SUCC""
    },
    ""channel"": 0,
    ""game_id"": ""29080"",
    ""openid"": """ + openid + @""",
    ""uid"": """ + uid + @""",
    ""biz_ticket"": """ + uid + @""",
    ""expire_interval"": 86400,
    ""refresh_interval"": 604800,
    ""login_key"": """ + uid + @""",
    ""login_ticket"": """ + uid + @""",
    ""third_uid"": """ + uid + @""",
    ""user_name"": """ + nickname + @"""
}";
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
