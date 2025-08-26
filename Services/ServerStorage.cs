using System.Text.Json;
using TilePinger.Models;

namespace TilePinger.Services
{
    public static class ServerStorage
    {
        private static string AppDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TilePinger");
        private static string ConfigPath => Path.Combine(AppDir, "servers.json");

        private static readonly Server[] DefaultServers = new[]
        {
            new Server { Name = "Google DNS", Host = "8.8.8.8" },
            new Server { Name = "Cloudflare", Host = "1.1.1.1" }
        };

        public static List<Server> Load()
        {
            try
            {
                if (File.Exists(ConfigPath))
                {
                    using var fs = File.OpenRead(ConfigPath);
                    var data = JsonSerializer.Deserialize<ServerList>(fs);
                    if (data?.Servers != null)
                        return data.Servers;
                }
            }
            catch { }
            Save(DefaultServers.ToList());
            return DefaultServers.ToList();
        }

        public static void Save(List<Server> servers)
        {
            Directory.CreateDirectory(AppDir);
            var data = new ServerList { Servers = servers };
            var opts = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(ConfigPath, JsonSerializer.Serialize(data, opts));
        }

        private class ServerList
        {
            public List<Server> Servers { get; set; } = new();
        }
    }
}
