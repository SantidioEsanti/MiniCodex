namespace MiniCodex.Core.Services;

public class ScanProgress
{
    public int TotalFiles { get; set; }
    public int ProcessedFiles { get; set; }
    public string? CurrentFile { get; set; }
    public int Added { get; set; }
    public int Updated { get; set; }
    public int Skipped { get; set; }
    public int Errors { get; set; }
    public string? LastError { get; set; }

    public double Percent => TotalFiles > 0 ? (double)ProcessedFiles / TotalFiles * 100 : 0;
}