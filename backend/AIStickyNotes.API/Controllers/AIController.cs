using AIStickyNotes.API.Models;
using AIStickyNotes.API.Services;
using Microsoft.AspNetCore.Mvc;

namespace AIStickyNotes.API.Controllers;

[ApiController]
[Route("api/ai")]
public class AIController : ControllerBase
{
    private readonly IAIService _aiService;
    private readonly ILogger<AIController> _logger;

    public AIController(IAIService aiService, ILogger<AIController> logger)
    {
        _aiService = aiService;
        _logger = logger;
    }

    /// <summary>
    /// Summarizes the provided note text using AI.
    /// </summary>
    [HttpPost("summarize")]
    [ProducesResponseType(typeof(SummarizeResponse), 200)]
    [ProducesResponseType(400)]
    [ProducesResponseType(500)]
    public async Task<IActionResult> Summarize([FromBody] SummarizeRequest request)
    {
        if (string.IsNullOrWhiteSpace(request.Text))
            return BadRequest(new { error = "Text cannot be empty." });

        if (request.Text.Length > 10_000)
            return BadRequest(new { error = "Text exceeds maximum allowed length of 10,000 characters." });

        try
        {
            _logger.LogInformation("Summarizing note of length {Length}", request.Text.Length);
            var summary = await _aiService.SummarizeAsync(request.Text);
            return Ok(new SummarizeResponse { Summary = summary });
        }
        catch (InvalidOperationException ex)
        {
            _logger.LogError(ex, "Configuration error");
            return StatusCode(500, new { error = "AI service is not properly configured." });
        }
        catch (HttpRequestException ex)
        {
            _logger.LogError(ex, "AI provider request failed");
            return StatusCode(502, new { error = "Unable to reach AI provider. Please try again." });
        }
        catch (Exception ex)
        {
            _logger.LogError(ex, "Unexpected error during summarization");
            return StatusCode(500, new { error = "An unexpected error occurred." });
        }
    }

    /// <summary>
    /// Health check endpoint.
    /// </summary>
    [HttpGet("health")]
    public IActionResult Health() => Ok(new { status = "ok", timestamp = DateTime.UtcNow });
}
