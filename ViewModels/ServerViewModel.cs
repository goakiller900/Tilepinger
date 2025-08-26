using System.ComponentModel;
using System.Runtime.CompilerServices;
using System.Windows.Media;
using TilePinger.Models;

namespace TilePinger.ViewModels
{
    public class ServerViewModel : INotifyPropertyChanged
    {
        public Server Model { get; }
        public string Name => Model.Name;
        public string Host => Model.Host;

        private string _status = "⏳ checking...";
        public string Status { get => _status; set { _status = value; OnPropertyChanged(); } }

        private string _roundtrip = string.Empty;
        public string Roundtrip { get => _roundtrip; set { _roundtrip = value; OnPropertyChanged(); } }

        private Brush _background = Brushes.Gainsboro;
        public Brush Background { get => _background; set { _background = value; OnPropertyChanged(); } }

        public ServerViewModel(Server s)
        {
            Model = s;
        }

        public event PropertyChangedEventHandler? PropertyChanged;
        private void OnPropertyChanged([CallerMemberName] string? name = null) => PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(name));
    }
}
