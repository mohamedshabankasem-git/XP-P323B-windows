using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Windows.Graphics.Printing.Workflow;

namespace PrintSupportApp;

public partial class App : Application
{
    private Window? _window;

    public App()
    {
        InitializeComponent();
    }

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        var activation = Microsoft.Windows.AppLifecycle.AppInstance.GetCurrent().GetActivatedEventArgs();
        _window = new Window();
        var frame = new Frame();

        if (activation.Kind == Microsoft.Windows.AppLifecycle.ExtendedActivationKind.PrintSupportJobUI &&
            activation.Data is PrintWorkflowJobActivatedEventArgs jobArgs)
        {
            frame.Navigate(typeof(JobActivatedPage), jobArgs);
        }
        else
        {
            frame.Navigate(typeof(HomePage));
        }

        _window.Content = frame;
        _window.Activate();
    }
}
