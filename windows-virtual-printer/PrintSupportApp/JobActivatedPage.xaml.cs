using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Navigation;
using Windows.Foundation;
using Windows.Graphics.Printing.Workflow;

namespace PrintSupportApp;

public sealed partial class JobActivatedPage : Page
{
    private PrintWorkflowJobUISession? _session;
    private Deferral? _uiDeferral;
    private PrintWorkflowVirtualPrinterUIEventArgs? _virtualPrinterArgs;
    private bool _finished;

    public JobActivatedPage()
    {
        InitializeComponent();
    }

    protected override void OnNavigatedTo(NavigationEventArgs e)
    {
        base.OnNavigatedTo(e);
        if (e.Parameter is not PrintWorkflowJobActivatedEventArgs activation)
        {
            StatusText.Text = "تعذر قراءة بيانات مهمة الطباعة.";
            return;
        }

        _session = activation.Session;
        _session.VirtualPrinterUIDataAvailable += OnVirtualPrinterUiDataAvailable;
        _session.Start();
        StatusText.Text = "تم فتح واجهة مهمة الطباعة. انتظر تجهيز المستند...";
    }

    private void OnVirtualPrinterUiDataAvailable(
        PrintWorkflowJobUISession sender,
        PrintWorkflowVirtualPrinterUIEventArgs args)
    {
        _uiDeferral = args.GetDeferral();
        _virtualPrinterArgs = args;
        DispatcherQueue.TryEnqueue(() =>
        {
            StatusText.Text = "المستند جاهز. عند المتابعة سيتم تسليمه إلى تطبيق XP-P323B.";
            ContinueButton.IsEnabled = true;
        });
    }

    private void OnContinue(object sender, RoutedEventArgs e) => CompleteUi();

    private void OnCancel(object sender, RoutedEventArgs e)
    {
        _virtualPrinterArgs?.Configuration.AbortPrintFlow(
            PrintWorkflowJobAbortReason.UserCanceled);
        CompleteUi();
    }

    private void CompleteUi()
    {
        if (_finished) return;
        _finished = true;
        _uiDeferral?.Complete();
        _uiDeferral = null;
        Application.Current.Exit();
    }
}
