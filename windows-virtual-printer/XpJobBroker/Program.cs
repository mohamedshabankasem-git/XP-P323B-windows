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
            RemoveExpiredFiles(packageJobs);

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
                    if (string.IsNullOrWhiteSpace(id) || !Guid.TryParseExact(id, "N", out _) ||
                        string.IsNullOrWhiteSpace(convertedFile))
                        throw new InvalidDataException("The print job metadata is incomplete or invalid.");

                    var sourcePath = Path.Combine(packageJobs, Path.GetFileName(convertedFile));
                    if (!File.Exists(sourcePath))
                        throw new FileNotFoundException("The converted PDF is missing.", sourcePath);
                    var sourceInfo = new FileInfo(sourcePath);
                    if (sourceInfo.Length <= 0 || sourceInfo.Length > 256L * 1024 * 1024)
                        throw new InvalidDataException("The converted PDF is empty or exceeds the 256 MB job limit.");

                    var targetPath = Path.Combine(staging, id + ".pdf");
                    File.Copy(sourcePath, targetPath, overwrite: true);

                    var start = new ProcessStartInfo(appExe)
                    {
                        UseShellExecute = true,
                        WorkingDirectory = Path.GetDirectoryName(appExe)!,
                        Arguments = "\"" + targetPath + "\""
                    };
                    var launched = Process.Start(start);
                    if (launched is null)
                        throw new InvalidOperationException("Windows did not start the XP-P323B desktop application.");

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
