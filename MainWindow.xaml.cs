using System;
using System.Collections.ObjectModel;
using System.Linq;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using TilePinger.Models;
using TilePinger.Services;
using TilePinger.ViewModels;
using System.Windows.Media;

namespace TilePinger
{
    public partial class MainWindow : Window
    {
        private readonly ObservableCollection<ServerViewModel> _servers = new();
        private AppSettings _settings;
        private DispatcherTimer? _timer;
        private PingService _pingService;

        public MainWindow()
        {
            InitializeComponent();
            _settings = SettingsStorage.Load();
            _pingService = new PingService(_settings.TimeoutMs);
            foreach (var s in ServerStorage.Load())
            {
                _servers.Add(new ServerViewModel(s));
            }
            ServerItems.ItemsSource = _servers;
            StartTimer();
        }

        private void StartTimer()
        {
            _timer = new DispatcherTimer();
            _timer.Interval = TimeSpan.FromSeconds(_settings.RefreshSeconds);
            _timer.Tick += async (s, e) => await PingAll();
            _timer.Start();
            _ = PingAll();
        }

        private async Task PingAll()
        {
            foreach (var vm in _servers)
            {
                vm.Status = "⏳ checking...";
                vm.Roundtrip = string.Empty;
                vm.Background = Brushes.Gainsboro;
                var reply = await _pingService.PingAsync(vm.Host);
                if (reply != null && reply.Status == System.Net.NetworkInformation.IPStatus.Success)
                {
                    vm.Status = "✅ online";
                    vm.Roundtrip = $"{reply.RoundtripTime} ms";
                    vm.Background = Brushes.LightGreen;
                }
                else if (reply != null && reply.Status == System.Net.NetworkInformation.IPStatus.TimedOut)
                {
                    vm.Status = "⚠️ timeout";
                    vm.Background = Brushes.Khaki;
                }
                else
                {
                    vm.Status = "❌ offline";
                    vm.Background = Brushes.LightCoral;
                }
            }
        }

        private async void AddButton_Click(object sender, RoutedEventArgs e)
        {
            var name = NameText.Text;
            var host = HostText.Text;
            if (string.IsNullOrWhiteSpace(host)) return;
            if (string.IsNullOrWhiteSpace(name)) name = host;
            var server = new Server { Name = name, Host = host };
            _servers.Add(new ServerViewModel(server));
            ServerStorage.Save(_servers.Select(v => v.Model).ToList());
            await PingAll();
            NameText.Clear();
            HostText.Clear();
        }
    }
}
