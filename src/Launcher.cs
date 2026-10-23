using System;
using System.Diagnostics;
using System.IO;
using System.Windows.Forms;

namespace AutoIngestStation
{
    static class Program
    {
        [STAThread]
        static void Main()
        {
            try
            {
                string baseDir = AppDomain.CurrentDomain.BaseDirectory;
                string userProfile = Environment.GetFolderPath(Environment.SpecialFolder.UserProfile);

                string[] candidatePaths = new string[]
                {
                    Path.Combine(baseDir, "src", "App-Desktop.ps1"),
                    Path.Combine(baseDir, "App-Desktop.ps1"),
                    Path.Combine(baseDir, "..", "src", "App-Desktop.ps1"),
                    Path.Combine(userProfile, "Documents", "GitHub", "auto-ingest-station", "src", "App-Desktop.ps1"),
                    Path.Combine(@"C:\auto-ingest-station", "src", "App-Desktop.ps1")
                };

                string foundScript = null;
                foreach (string candidate in candidatePaths)
                {
                    try
                    {
                        string fullPath = Path.GetFullPath(candidate);
                        if (File.Exists(fullPath))
                        {
                            foundScript = fullPath;
                            break;
                        }
                    }
                    catch { }
                }

                if (foundScript == null)
                {
                    MessageBox.Show(
                        "Arquivo de aplicativo não encontrado em nenhum dos seguintes locais:\n\n" +
                        string.Join("\n", candidatePaths),
                        "Erro - Estação DIT",
                        MessageBoxButtons.OK,
                        MessageBoxIcon.Error
                    );
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + foundScript + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WorkingDirectory = Path.GetDirectoryName(foundScript);

                Process proc = Process.Start(psi);
                proc.WaitForExit();
            }
            catch (Exception ex)
            {
                MessageBox.Show("Erro ao iniciar a Estação DIT:\n" + ex.Message, "Erro Crítico", MessageBoxButtons.OK, MessageBoxIcon.Error);
            }
        }
    }
}
