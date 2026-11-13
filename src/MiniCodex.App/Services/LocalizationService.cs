using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;
using System.Text.Json;

namespace MiniCodex.App.Services;

public class LocalizationService
{
    private readonly AppPaths _paths;
    private Dictionary<string, string> _dict = new(StringComparer.OrdinalIgnoreCase);
    private Dictionary<string, string> _fallback = new(StringComparer.OrdinalIgnoreCase);

    public string Current { get; private set; } = "en";

    public LocalizationService(AppPaths paths, string current)
    {
        _paths = paths;
        Current = current;
    }

    public void LoadInitial()
    {
        var sys = CultureInfo.CurrentUICulture.TwoLetterISOLanguageName;
        var lang = File.Exists(Path.Combine(_paths.LangDir, sys + ".json")) ? sys : "en";
        SetLanguage(lang);
    }

    public void SetLanguage(string lang)
    {
        Current = lang;
        _fallback = Load("en");
        _dict = lang == "en" ? _fallback : Load(lang);
    }

    public string Get(string key)
    {
        if (_dict.TryGetValue(key, out var v)) return v;
        if (_fallback.TryGetValue(key, out var f)) return f;
        return key;
    }

    private Dictionary<string, string> Load(string lang)
    {
        var result = new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);
        var path = Path.Combine(_paths.LangDir, lang + ".json");
        if (!File.Exists(path)) return result;
        using var doc = JsonDocument.Parse(File.ReadAllText(path));
        Flatten(doc.RootElement, "", result);
        return result;
    }

    private static void Flatten(JsonElement el, string prefix, Dictionary<string, string> target)
    {
        foreach (var prop in el.EnumerateObject())
        {
            var key = string.IsNullOrEmpty(prefix) ? prop.Name : prefix + "." + prop.Name;
            if (prop.Value.ValueKind == JsonValueKind.Object)
                Flatten(prop.Value, key, target);
            else if (prop.Value.ValueKind == JsonValueKind.String)
                target[key] = prop.Value.GetString() ?? "";
        }
    }
}