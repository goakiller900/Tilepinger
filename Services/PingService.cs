using System.Net.NetworkInformation;

namespace TilePinger.Services
{
    public class PingService
    {
        private readonly int _timeoutMs;
        public PingService(int timeoutMs) => _timeoutMs = timeoutMs;

        public async Task<PingReply?> PingAsync(string host)
        {
            try
            {
                using var ping = new Ping();
                return await ping.SendPingAsync(host, _timeoutMs);
            }
            catch
            {
                return null;
            }
        }
    }
}
