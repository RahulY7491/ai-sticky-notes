namespace AIStickyNotes.API.Models;

public class SummarizeRequest
{
    public string Text { get; set; } = string.Empty;
}

public class SummarizeResponse
{
    public string Summary { get; set; } = string.Empty;
}
