namespace TilePinger.Models
{
    public class AppSettings
    {
        public int RefreshSeconds { get; set; } = 5;
        public int TimeoutMs { get; set; } = 2000;
    }
}
