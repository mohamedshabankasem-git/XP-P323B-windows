using System.Diagnostics;
using System.Text.Json;
using Microsoft.Win32;

internal static class Program
{
    private const string RegistryKeyPath = @"Software\XP-P323B\Windows";

    private static int Main()
    {
        try
        {
            var localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            var packageRoot = Path.Combine(localAppData, "Packages");
            var packageJobs = Directory.Exists(packageRoot)
                ? Directory.GetDirectories(packageRoot, "XP323B.VirtualPrinter_*")
                    .Select(path => Path.Combine(path, "LocalState", "VirtualPrinterJobs"))
                    .FirstOrDefault(Directory.Exists)
                : null;

            if (packageJobs is null)
                return 2;

            var appExe = Registry.GetValue(
                $@"HKEY_CURRENT_USER\{RegistryKeyPath}",
                "AppExePath",
                null) as string;
            if (string.IsNullOrWhiteSpace(appExe) || !File.Exists(appExe))
                return 3;

            var staging = Path.Combine(localAppData, "XP-P323B", "VirtualPrinterJobs");
            Directory.CreateDirectory(staging);
            RemoveExpiredFiles(staging);

            foreach (var metadataPath in Directory.EnumerateFiles(packageJobs, "*.json"))
            {
                var claimPath = metadataPath + ".processing";
                try
                {
                    File.Move(metadataPath, claimPath);
                }
                catch (IOException)
                {
                    continue;
                }

                try
                {
                    using var document = JsonDocument.Parse(File.ReadAllText(claimPath));
                    var root = document.RootElement;
                    var id = root.GetProperty("id").GetString();
                    var convertedFile = root.GetProperty("convertedFile").GetString();
                    if (string.IsNullOrWhiteSpace(id) || string.IsNullOrWhiteSpace(convertedFile))
                        throw new InvalidDataException("The print job metadata is incomplete.");

                    var sourcePath = Path.Combine(packageJobs, Path.GetFileName(convertedFile));
                    if (!File.Exists(sourcePath))
                        throw new FileNotFoundException("The converted PDF is missing.", sourcePath);

                    var targetPath = Path.Combine(staging, id + ".pdf");
                    File.Copy(sourcePath, targetPath, overwrite: true);

                    var start = new ProcessStartInfo(appExe)
                    {
                        UseShellExecute = true,
                        WorkingDirectory = Path.GetDirectoryName(appExe)!
                    };
                    start.ArgumentList.Add(targetPath);
                    Process.Start(start);

                    File.WriteAllText(Path.Combine(staging, id + ".dispatched"), DateTimeOffset.UtcNow.ToString("O"));
                    File.Delete(claimPath);
                }
                catch
                {
                    if (File.Exists(claimPath) && !File.Exists(metadataPath))
                        File.Move(claimPath, metadataPath);
                    throw;
                }
            }

            return 0;
        }
        catch (Exception exception)
        {
            var logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                "XP-P323B", "Logs");
            Directory.CreateDirectory(logDirectory);
            File.AppendAllText(Path.Combine(logDirectory, "virtual-printer-broker.log"),
                $"[{DateTimeOffset.UtcNow:O}] {exception}{Environment.NewLine}");
            return 1;
        }
    }

    private static void RemoveExpiredFiles(string directory)
    {
        foreach (var file in Directory.EnumerateFiles(directory))
        {
            try
            {
                if (DateTime.UtcNow - File.GetLastWriteTimeUtc(file) > TimeSpan.FromHours(24))
                    File.Delete(file);
            }
            catch
            {
                // An in-use document is left for a later cleanup pass.
            }
        }
    }
}
