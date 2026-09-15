use semver::Version;
use std::time::Duration;

fn version(tag: &str) -> Result<Version, String> {
    let tag = tag.trim_start_matches('v');
    let normalized = if tag.split('.').count() == 2 {
        format!("{tag}.0")
    } else {
        tag.to_owned()
    };
    Version::parse(&normalized)
        .map_err(|_| "The release version could not be compared safely.".to_string())
}

fn summary(current: &str, latest: &str) -> Result<String, String> {
    let installed = version(current)?;
    let released = version(latest)?;
    let result = if released > installed {
        "A newer release is available. Visit Help > GitHub Repository for release notes and downloads."
    } else if !installed.pre.is_empty() {
        "You are using a development build. The latest published release is not newer than this build."
    } else {
        "No newer published release was found."
    };
    Ok(format!("Desktop version: {current}\nLatest published release: {latest}\n\n{result}\n\nNothing has been downloaded or installed."))
}

fn latest_tag(tags: &serde_json::Value) -> Result<String, String> {
    let tags = tags
        .as_array()
        .ok_or("GitHub returned an unreadable tag list.")?;
    tags.iter()
        .filter_map(|tag| tag["name"].as_str())
        .filter_map(|name| version(name).ok().map(|parsed| (parsed, name)))
        .filter(|(parsed, _)| parsed.pre.is_empty())
        .max_by(|(left, _), (right, _)| left.cmp(right))
        .map(|(_, name)| name.to_owned())
        .ok_or_else(|| "No versioned release tag was found.".to_string())
}

pub fn check(current: &str) -> Result<String, String> {
    // User-initiated only. Do not send engine credentials, paths or participant data.
    let client = reqwest::blocking::Client::builder()
        .timeout(Duration::from_secs(15))
        .user_agent("Convert-Pheno-desktop-release-check")
        .build()
        .map_err(|e| e.to_string())?;
    let response = client.get("https://api.github.com/repos/CNAG-Biomedical-Informatics/convert-pheno/tags?per_page=100")
        .header("Accept", "application/vnd.github+json")
        .send().map_err(|_| "GitHub could not be reached. Check your internet connection.".to_string())?;
    let response = response.error_for_status().map_err(|e| {
        format!(
            "GitHub returned an error: {}",
            e.status().map(|s| s.to_string()).unwrap_or_default()
        )
    })?;
    let tags: serde_json::Value = response
        .json()
        .map_err(|_| "GitHub returned an unreadable tag response.".to_string())?;
    summary(current, &latest_tag(&tags)?)
}

#[cfg(test)]
mod tests {
    use super::*;
    #[test]
    fn compares_published_and_development_versions() {
        assert!(summary("0.35.0-dev", "v0.34")
            .unwrap()
            .contains("development build"));
        assert!(summary("0.35.0-dev", "v0.35")
            .unwrap()
            .contains("newer release"));
        assert!(summary("0.35.0", "v0.35").unwrap().contains("No newer"));
        assert!(summary("0.9.0", "v0.10").unwrap().contains("newer release"));
        assert!(summary("0.35.0", "unknown").is_err());
        let tags =
            serde_json::json!([{"name":"notes"},{"name":"0.9"},{"name":"v0.10"},{"name":"0.11_1"}]);
        assert_eq!(latest_tag(&tags).unwrap(), "v0.10");
    }
}
