using System.Text;
using System.Text.Json;
using AIStickyNotes.API.Models;

namespace AIStickyNotes.API.Services;

public interface IAIService
{
    Task<string> SummarizeAsync(string text);
}

public class AIService : IAIService
{
    private readonly HttpClient _http;
    private readonly IConfiguration _config;
    private readonly ILogger<AIService> _logger;

    public AIService(HttpClient http, IConfiguration config, ILogger<AIService> logger)
    {
        _http = http;
        _config = config;
        _logger = logger;
    }

    public async Task<string> SummarizeAsync(string text)
    {
        var apiKey = _config["Gemini:ApiKey"];
        if (string.IsNullOrEmpty(apiKey))
            throw new InvalidOperationException("Gemini API key is not configured.");

        var url = $"https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key={apiKey}";

        var prompt = $"""
            Summarize the following note in 2-3 concise sentences. 
            Keep it clear and action-oriented. 
            Return ONLY the summary, no extra commentary.

            Note:
            {text}
            """;

        var payload = new
        {
            contents = new[]
            {
                new { parts = new[] { new { text = prompt } } }
            },
            generationConfig = new { maxOutputTokens = 256, temperature = 0.3 }
        };

        var json = JsonSerializer.Serialize(payload);
        int[] delaysMs = [0, 5000, 15000];
        HttpResponseMessage response = null!;

        for (int attempt = 0; attempt < delaysMs.Length; attempt++)
        {
            if (delaysMs[attempt] > 0)
            {
                _logger.LogWarning("Rate limited by Gemini. Retrying in {Delay}ms (attempt {Attempt})...",
                    delaysMs[attempt], attempt + 1);
                await Task.Delay(delaysMs[attempt]);
            }
            var content = new StringContent(json, Encoding.UTF8, "application/json");
            response = await _http.PostAsync(url, content);
            if ((int)response.StatusCode != 429) break;
        }

        if (!response!.IsSuccessStatusCode)
        {
            var errorBody = await response.Content.ReadAsStringAsync();
            _logger.LogError("Gemini API error {Status}: {Body}", (int)response.StatusCode, errorBody);
            response.EnsureSuccessStatusCode();
        }

        var responseJson = await response.Content.ReadAsStringAsync();
        using var doc = JsonDocument.Parse(responseJson);

        var summary = doc
            .RootElement
            .GetProperty("candidates")[0]
            .GetProperty("content")
            .GetProperty("parts")[0]
            .GetProperty("text")
            .GetString() ?? "Unable to generate summary.";

        return summary.Trim();
    }
}
