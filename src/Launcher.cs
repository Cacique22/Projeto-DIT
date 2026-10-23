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
                string scriptPath = Path.Combine(baseDir, "src", "App-Desktop.ps1");
                if (!File.Exists(scriptPath))
                {
                    scriptPath = Path.Combine(baseDir, "App-Desktop.ps1");
                }

                if (!File.Exists(scriptPath))
                {
                    MessageBox.Show("Arquivo de aplicativo não encontrado:\n" + scriptPath, "Erro - Estação DIT", MessageBoxButtons.OK, MessageBoxIcon.Error);
                    return;
                }

                ProcessStartInfo psi = new ProcessStartInfo();
                psi.FileName = "powershell.exe";
                psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File \"" + scriptPath + "\"";
                psi.UseShellExecute = false;
                psi.CreateNoWindow = true;
                psi.WorkingDirectory = Path.GetDirectoryName(scriptPath);

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
