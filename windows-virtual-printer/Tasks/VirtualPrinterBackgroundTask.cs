using System;
using System.Text.Json;
using Windows.ApplicationModel;
using Windows.ApplicationModel.Background;
using Windows.Graphics.Printing.Workflow;
using Windows.Storage;

namespace Tasks;

public sealed class VirtualPrinterBackgroundTask : IBackgroundTask
{
    private BackgroundTaskDeferral? _deferral;

    public void Run(IBackgroundTaskInstance taskInstance)
    {
        _deferral = taskInstance.GetDeferral();
        if (taskInstance.TriggerDetails is not PrintWorkflowVirtualPrinterTriggerDetails details)
        {
            CompleteTask();
            return;
        }

        var session = details.VirtualPrinterSession;
        session.VirtualPrinterDataAvailable += OnVirtualPrinterDataAvailable;
        session.Start();
    }

    private async void OnVirtualPrinterDataAvailable(
        PrintWorkflowVirtualPrinterSession sender,
        PrintWorkflowVirtualPrinterDataAvailableEventArgs args)
    {
        var status = PrintWorkflowSubmittedStatus.Failed;
        string? jobId = null;

        try
        {
            var uiResult = await args.UILauncher.LaunchAndCompleteUIAsync();
            if (uiResult == PrintWorkflowUICompletionStatus.UserCanceled)
            {
                status = PrintWorkflowSubmittedStatus.Canceled;
                return;
            }
            if (uiResult != PrintWorkflowUICompletionStatus.Completed)
                throw new InvalidOperationException($"Print UI failed: {uiResult}");

            var contentType = args.SourceContent.ContentType;
            if (!string.Equals(contentType, "application/oxps", StringComparison.OrdinalIgnoreCase))
                throw new NotSupportedException($"Unsupported print payload: {contentType}");

            jobId = Guid.NewGuid().ToString("N");
            var jobsFolder = await ApplicationData.Current.LocalFolder.CreateFolderAsync(
                "VirtualPrinterJobs", CreationCollisionOption.OpenIfExists);
            var pdfFile = await jobsFolder.CreateFileAsync(
                $"{jobId}.pdf", CreationCollisionOption.FailIfExists);

            using (var output = await pdfFile.OpenAsync(FileAccessMode.ReadWrite))
            {
                var converter = args.GetPdlConverter(PrintWorkflowPdlConversionType.XpsToPdf);
                var printTicket = args.GetJobPrintTicket();
                var input = args.SourceContent.GetInputStream();
                var outputStream = output.GetOutputStreamAt(0);
                await converter.ConvertPdlAsync(printTicket, input, outputStream);
                await outputStream.FlushAsync();
            }

            var metadata = new
            {
                id = jobId,
                createdUtc = DateTimeOffset.UtcNow,
                contentType,
                convertedFile = pdfFile.Name,
                state = "captured",
                packageFamilyName = Package.Current.Id.FamilyName
            };
            var metadataFile = await jobsFolder.CreateFileAsync(
                $"{jobId}.json", CreationCollisionOption.FailIfExists);
            await FileIO.WriteTextAsync(metadataFile, JsonSerializer.Serialize(metadata, new JsonSerializerOptions
            {
                WriteIndented = true
            }));

            status = PrintWorkflowSubmittedStatus.Succeeded;
        }
        catch (Exception exception)
        {
            try
            {
                var logFolder = await ApplicationData.Current.LocalFolder.CreateFolderAsync(
                    "VirtualPrinterJobs", CreationCollisionOption.OpenIfExists);
                var logFile = await logFolder.CreateFileAsync(
                    $"failed-{jobId ?? Guid.NewGuid().ToString("N")}.txt",
                    CreationCollisionOption.ReplaceExisting);
                await FileIO.WriteTextAsync(logFile, exception.ToString());
            }
            catch { }
        }
        finally
        {
            args.CompleteJob(status);
            CompleteTask();
        }
    }

    private void CompleteTask()
    {
        _deferral?.Complete();
        _deferral = null;
    }
}
