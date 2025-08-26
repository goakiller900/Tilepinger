using System.Text.Json;
using TilePinger.Models;

namespace TilePinger.Services
{
    public static class SettingsStorage
    {
        private static string AppDir => Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "TilePinger");
        private static string SettingsPath => Path.Combine(AppDir, "settings.json");

        public static AppSettings Load()
        {
            try
            {
                if (File.Exists(SettingsPath))
                {
                    var text = File.ReadAllText(SettingsPath);
                    var settings = JsonSerializer.Deserialize<AppSettings>(text);
                    if (settings != null) return settings;
                }
            }
            catch { }
            var def = new AppSettings();
            Save(def);
            return def;
        }

        public static void Save(AppSettings settings)
        {
            Directory.CreateDirectory(AppDir);
            var opts = new JsonSerializerOptions { WriteIndented = true };
            File.WriteAllText(SettingsPath, JsonSerializer.Serialize(settings, opts));
        }
    }
}
