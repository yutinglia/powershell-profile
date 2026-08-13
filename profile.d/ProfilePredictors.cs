using System;
using System.Collections.Generic;
using System.Management.Automation;
using System.Management.Automation.Subsystem;
using System.Management.Automation.Subsystem.Prediction;
using System.Threading;

public sealed class ProfileCommandPredictor : ICommandPredictor
{
    public static readonly Guid PredictorId = new Guid("3f8c1a72-9d4e-4b6a-a1c0-7e5d92f4b8e1");
    private readonly string[] _names;
    private readonly string[] _tips;

    public ProfileCommandPredictor(string[] names, string[] tips)
    {
        _names = names ?? Array.Empty<string>();
        _tips = tips ?? Array.Empty<string>();
    }

    public Guid Id { get { return PredictorId; } }
    public string Name { get { return "Profile"; } }
    public string Description { get { return "Suggests commands from this PowerShell profile"; } }
    public Dictionary<string, ScriptBlock> FunctionsToDefine { get { return null; } }

    public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
    {
        string input = context.InputAst.Extent.Text;
        if (string.IsNullOrWhiteSpace(input) || input.IndexOf(' ') >= 0)
        {
            return default(SuggestionPackage);
        }

        var results = new List<PredictiveSuggestion>();
        for (int i = 0; i < _names.Length; i++)
        {
            string name = _names[i];
            if (name.Length > input.Length &&
                name.StartsWith(input, StringComparison.OrdinalIgnoreCase))
            {
                string tip = (i < _tips.Length) ? _tips[i] : null;
                if (string.IsNullOrEmpty(tip))
                {
                    results.Add(new PredictiveSuggestion(name));
                }
                else
                {
                    results.Add(new PredictiveSuggestion(name, tip));
                }
            }
        }

        return results.Count == 0 ? default(SuggestionPackage) : new SuggestionPackage(results);
    }

    public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback)
    {
        return false;
    }

    public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
    public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }
    public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history) { }
    public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
}

public sealed class ProfileHistoryPredictor : ICommandPredictor
{
    public static readonly Guid PredictorId = new Guid("8b2e9f14-6c47-4a1d-b3e8-5d70c91a4f26");
    private readonly HashSet<string> _profileNames;
    private readonly object _gate = new object();
    private string[] _history;

    public ProfileHistoryPredictor(string[] profileNames, string[] history)
    {
        _profileNames = new HashSet<string>(
            profileNames ?? Array.Empty<string>(),
            StringComparer.OrdinalIgnoreCase);
        _history = history ?? Array.Empty<string>();
    }

    public Guid Id { get { return PredictorId; } }
    public string Name { get { return "History"; } }
    public string Description { get { return "Suggests PSReadLine history except bare profile commands"; } }
    public Dictionary<string, ScriptBlock> FunctionsToDefine { get { return null; } }

    public SuggestionPackage GetSuggestion(PredictionClient client, PredictionContext context, CancellationToken cancellationToken)
    {
        string input = context.InputAst.Extent.Text;
        if (string.IsNullOrWhiteSpace(input))
        {
            return default(SuggestionPackage);
        }

        string[] hist;
        lock (_gate)
        {
            hist = _history;
        }

        var results = new List<PredictiveSuggestion>();
        var seen = new HashSet<string>(StringComparer.OrdinalIgnoreCase);
        for (int i = hist.Length - 1; i >= 0; i--)
        {
            string line = hist[i];
            if (string.IsNullOrEmpty(line) || line.Length < input.Length)
            {
                continue;
            }
            if (_profileNames.Contains(line))
            {
                continue;
            }
            if (line.IndexOf(input, StringComparison.OrdinalIgnoreCase) < 0)
            {
                continue;
            }
            if (!seen.Add(line))
            {
                continue;
            }

            results.Add(new PredictiveSuggestion(line));
            if (results.Count >= 20)
            {
                break;
            }
        }

        return results.Count == 0 ? default(SuggestionPackage) : new SuggestionPackage(results);
    }

    public bool CanAcceptFeedback(PredictionClient client, PredictorFeedbackKind feedback)
    {
        return feedback == PredictorFeedbackKind.CommandLineAccepted;
    }

    public void OnSuggestionDisplayed(PredictionClient client, uint session, int countOrIndex) { }
    public void OnSuggestionAccepted(PredictionClient client, uint session, string acceptedSuggestion) { }

    public void OnCommandLineAccepted(PredictionClient client, IReadOnlyList<string> history)
    {
        var arr = new string[history.Count];
        for (int i = 0; i < history.Count; i++)
        {
            arr[i] = history[i];
        }
        lock (_gate)
        {
            _history = arr;
        }
    }

    public void OnCommandLineExecuted(PredictionClient client, string commandLine, bool success) { }
}
