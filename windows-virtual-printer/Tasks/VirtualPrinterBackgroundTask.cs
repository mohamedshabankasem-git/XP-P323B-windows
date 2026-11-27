using System;
using System.Text.Json;
using Windows.ApplicationModel;
using Windows.ApplicationModel.Background;
using Windows.Graphics.Printing.Workflow;
using Windows.Storage;

namespace Tasks;

/// <summary>
/// Receives a virtual-printer job and converts the Windows OXPS payload to PDF.
/// The Flutter handoff is intentionally a separate, not-yet-enabled integration phase.
/// </summary>
public sealed class VirtualPrinterBackgroundTask : IBackgroundTask
{
    private BackgroundTaskDeferral? _deferral;

    public void Run(IBackgroundTaskInstance taskInstance)
    {
        _deferral = taskInstance.GetDeferral();

        if (taskInstance.TriggerDetails is not PrintWorkflowVirtualPrinterTriggerDetails details)
        {
            _deferral.Complete();
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
            var contentType = args.SourceContent.ContentType;
            if (!string.Equals(contentType, "application/oxps", StringComparison.OrdinalIgnoreCase))
            {
                throw new NotSupportedException($"Unsupported print payload: {contentType}");
            }

            jobId = Guid.NewGuid().ToString("N");
            var jobsFolder = await ApplicationData.Current.LocalFolder.CreateFolderAsync(
                "VirtualPrinterJobs",
                CreationCollisionOption.OpenIfExists);

            var pdfFile = await jobsFolder.CreateFileAsync(
                $"{jobId}.pdf",
                CreationCollisionOption.FailIfExists);

            await using (var output = await pdfFile.OpenAsync(Windows.Storage.FileAccessMode.ReadWrite))
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

            var json = JsonSerializer.Serialize(metadata, new JsonSerializerOptions
            {
                WriteIndented = true
            });

            var metadataFile = await jobsFolder.CreateFileAsync(
                $"{jobId}.json",
                CreationCollisionOption.FailIfExists);
            await FileIO.WriteTextAsync(metadataFile, json);

            // Mark the spooler job successful only after the complete converted file
            // and metadata have been persisted in the package's private storage.
            status = PrintWorkflowSubmittedStatus.Succeeded;
        }
        catch (Exception exception)
        {
            try
            {
                var logFolder = await ApplicationData.Current.LocalFolder.CreateFolderAsync(
                    "VirtualPrinterJobs",
                    CreationCollisionOption.OpenIfExists);
                var logFile = await logFolder.CreateFileAsync(
                    $"failed-{jobId ?? Guid.NewGuid().ToString("N")}.txt",
                    CreationCollisionOption.ReplaceExisting);
                await FileIO.WriteTextAsync(logFile, exception.ToString());
            }
            catch
            {
                // Preserve the original failed job status if diagnostic logging fails.
            }
        }
        finally
        {
            args.CompleteJob(status);
            _deferral?.Complete();
            _deferral = null;
        }
    }
}
