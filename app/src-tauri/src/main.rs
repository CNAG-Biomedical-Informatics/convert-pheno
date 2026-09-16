#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

use reqwest::blocking::Client;
use serde::Serialize;
use serde_json::{json, Value};
use sha2::{Digest, Sha256};
use std::{
    fs::{File, OpenOptions},
    io::{Read, Write},
    net::TcpListener,
    path::{Path, PathBuf},
    process::{Child, Command, Stdio},
    sync::{Mutex, atomic::{AtomicBool, Ordering}},
    time::Duration,
};
use tauri::{
    menu::{Menu, MenuItem, PredefinedMenuItem, Submenu},
    Emitter, Manager,
};
use tauri_plugin_dialog::DialogExt;
mod release_check;

#[derive(Clone, Serialize)]
struct Connection {
    url: String,
    token: String,
    #[serde(rename = "outputRoot")]
    output_root: String,
}
struct Engine {
    connection: Connection,
    local_token: String,
    child: Mutex<Child>,
    client: Client,
    resource_dir: Mutex<PathBuf>,
    resource_preferences: PathBuf,
    ohdsi_bytes: u64,
    ohdsi_sha256: String,
    ohdsi_url: String,
    resource_install: Mutex<()>,
    cancel_download: AtomicBool,
}
impl Engine {
    fn stop(&self) {
        let _ = self
            .client
            .post(format!("{}/api/shutdown", self.connection.url))
            .bearer_auth(&self.connection.token)
            .header("X-Convert-Pheno-Local", &self.local_token)
            .send();
        if let Ok(mut child) = self.child.lock() {
            for _ in 0..20 {
                if child.try_wait().ok().flatten().is_some() {
                    return;
                }
                std::thread::sleep(Duration::from_millis(50));
            }
            let _ = child.kill();
            let _ = child.wait();
        }
    }
    fn json(&self, response: reqwest::blocking::Response) -> Result<Value, String> {
        let ok = response.status().is_success();
        let body: Value = response.json().map_err(|e| e.to_string())?;
        if !ok {
            return Err(body["error"]["message"]
                .as_str()
                .unwrap_or("The engine request failed")
                .to_string());
        }
        Ok(body["data"].clone())
    }
}
impl Drop for Engine {
    fn drop(&mut self) {
        self.stop()
    }
}

fn start_engine(app: &tauri::App) -> Result<Engine, Box<dyn std::error::Error>> {
    let root = if cfg!(debug_assertions) {
        PathBuf::from(env!("CARGO_MANIFEST_DIR"))
            .join("../..")
            .canonicalize()?
    } else {
        app.path().resource_dir()?.join("engine")
    };
    let perl = if cfg!(debug_assertions) {
        PathBuf::from("perl")
    } else {
        root.join(if cfg!(windows) {
            "runtime/bin/perl.exe"
        } else {
            "runtime/bin/perl"
        })
    };
    let listener = TcpListener::bind("127.0.0.1:0")?;
    let url = format!("http://127.0.0.1:{}", listener.local_addr()?.port());
    let token = uuid::Uuid::new_v4().simple().to_string();
    let local_token = uuid::Uuid::new_v4().simple().to_string();
    let app_data = app.path().app_local_data_dir()?;
    let state = app_data.join("runs");
    let resource_preferences = app_data.join("resource-settings.json");
    let resource_dir = read_resource_directory(&resource_preferences, &app_data.join("resources"))?;
    std::fs::create_dir_all(&state)?;
    // A selected external drive may be disconnected. Keep the app usable so
    // the user can reconnect it or choose another folder from Resources.
    if !resource_preferences.exists() { std::fs::create_dir_all(&resource_dir)?; }
    let manifest: Value =
        serde_json::from_slice(&std::fs::read(root.join("share/db/manifest.json"))?)?;
    let ohdsi = &manifest["databases"]["ohdsi"];
    let ohdsi_bytes = ohdsi["byteSize"]
        .as_u64()
        .ok_or("OHDSI byte size is missing")?;
    let ohdsi_sha256 = ohdsi["sha256"]
        .as_str()
        .ok_or("OHDSI checksum is missing")?
        .to_string();
    let ohdsi_url = ohdsi["downloadUrl"].as_str()
        .ok_or("OHDSI download URL is missing")?.to_string();
    let bundled_ohdsi_dir = root
        .join("share/db")
        .join(manifest["currentBundle"].as_str().unwrap_or("v0"));
    let ohdsi_dir = if !resource_preferences.exists() && cfg!(debug_assertions) && bundled_ohdsi_dir.join("ohdsi.db").is_file() {
        bundled_ohdsi_dir
    } else {
        resource_dir.clone()
    };
    let log_path = app_data.join("engine.log");
    let log = OpenOptions::new()
        .create(true)
        .truncate(true)
        .write(true)
        .open(&log_path)?;
    let error_log = log.try_clone()?;
    drop(listener);
    let api_origins = if cfg!(debug_assertions) {
        "tauri://localhost,http://tauri.localhost,https://tauri.localhost,http://127.0.0.1:1430"
    } else {
        "tauri://localhost,http://tauri.localhost,https://tauri.localhost"
    };
    let mut command = Command::new(perl);
    if !cfg!(debug_assertions) {
        let runtime_bin = root.join("runtime/bin");
        let mut path = vec![runtime_bin];
        if let Some(existing) = std::env::var_os("PATH") {
            path.extend(std::env::split_paths(&existing));
        }
        command.env("PATH", std::env::join_paths(path)?);
        #[cfg(target_os = "linux")]
        command.env("LD_LIBRARY_PATH", root.join("runtime/lib"));
        // macOS uses the @rpath references embedded during packaging. A global
        // DYLD_LIBRARY_PATH override can select incompatible libraries and was
        // observed to cause SIGKILL on macOS even though direct startup worked.
        #[cfg(target_os = "macos")]
        command.env_remove("DYLD_LIBRARY_PATH");
    }
    command
        .arg(root.join("api/perl/main.pl"))
        .args(["daemon", "-l", &url])
        .current_dir(&root)
        .env("CONVERT_PHENO_API_TOKEN", &token)
        .env("CONVERT_PHENO_LOCAL_TOKEN", &local_token)
        .env("CONVERT_PHENO_STATE_DIR", state)
        .env("CONVERT_PHENO_SHARE_DIR", root.join("share"))
        .env("CONVERT_PHENO_OHDSI_DB_DIR", ohdsi_dir)
        .env("CONVERT_PHENO_API_HOSTS", "127.0.0.1")
        .env("CONVERT_PHENO_API_ORIGINS", api_origins)
        .stdin(Stdio::null())
        .stdout(Stdio::from(log))
        .stderr(Stdio::from(error_log));
    #[cfg(windows)]
    {
        use std::os::windows::process::CommandExt;
        command.creation_flags(0x08000000);
    }
    let child = command.spawn()?;
    let engine = Engine {
        connection: Connection {
            url,
            token,
            output_root: app
                .path()
                .app_local_data_dir()?
                .join("runs")
                .to_string_lossy()
                .into_owned(),
        },
        local_token,
        child: Mutex::new(child),
        client: Client::builder()
            .no_proxy()
            .timeout(Duration::from_secs(5))
            .build()?,
        resource_dir: Mutex::new(resource_dir),
        resource_preferences,
        ohdsi_bytes,
        ohdsi_sha256,
        ohdsi_url,
        resource_install: Mutex::new(()),
        cancel_download: AtomicBool::new(false),
    };
    for _ in 0..100 {
        if engine
            .client
            .get(format!("{}/api/health", engine.connection.url))
            .bearer_auth(&engine.connection.token)
            .send()
            .is_ok_and(|r| r.status().is_success())
        {
            return Ok(engine);
        }
        if let Some(status) = engine.child.lock().unwrap().try_wait()? {
            let details = std::fs::read_to_string(&log_path).unwrap_or_default();
            let details = details.trim();
            return Err(if details.is_empty() {
                format!("The core engine exited during startup ({status}) without diagnostic output.").into()
            } else {
                format!("The core engine exited during startup ({status}): {details}").into()
            });
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err("The conversion engine did not become ready".into())
}

fn read_resource_directory(settings: &Path, default: &Path) -> Result<PathBuf, Box<dyn std::error::Error>> {
    if !settings.exists() { return Ok(default.to_path_buf()); }
    let value: Value = serde_json::from_slice(&std::fs::read(settings)?)?;
    let directory = PathBuf::from(value["directory"].as_str().ok_or("Resource folder setting is missing")?);
    if !directory.is_absolute() { return Err("Resource folder must be absolute".into()); }
    Ok(directory)
}

#[tauri::command]
fn resource_directory(engine: tauri::State<Engine>) -> Result<String, String> {
    Ok(engine.resource_dir.lock().map_err(|e| e.to_string())?.to_string_lossy().into_owned())
}

#[tauri::command]
async fn choose_resource_directory(app: tauri::AppHandle) -> Result<Option<String>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let engine = app.state::<Engine>();
        let _guard = engine.resource_install.try_lock()
            .map_err(|_| "Wait for the database installation to finish")?;
        let Some(selected) = app.dialog().file().blocking_pick_folder() else { return Ok(None); };
        let directory = selected.into_path().map_err(|e| e.to_string())?
            .canonicalize().map_err(|e| e.to_string())?;
        // Check writability before changing the engine or saving the preference.
        let probe = tempfile::NamedTempFile::new_in(&directory).map_err(|e| format!("Cannot write to this folder: {e}"))?;
        drop(probe);
        let mut settings = tempfile::NamedTempFile::new_in(engine.resource_preferences.parent().ok_or("Invalid settings directory")?)
            .map_err(|e| e.to_string())?;
        serde_json::to_writer(&mut settings, &json!({"directory":directory})).map_err(|e| e.to_string())?;
        settings.as_file().sync_all().map_err(|e| e.to_string())?;
        let response = engine.client.post(format!("{}/api/resources/local-directory", engine.connection.url))
            .bearer_auth(&engine.connection.token)
            .header("X-Convert-Pheno-Local", &engine.local_token)
            .json(&json!({"directory":directory})).send().map_err(|e| e.to_string())?;
        engine.json(response)?;
        // Keep the running app consistent even if saving the preference fails.
        *engine.resource_dir.lock().map_err(|e| e.to_string())? = directory.clone();
        settings.persist(&engine.resource_preferences)
            .map_err(|e| format!("The folder is active, but could not be saved for next launch: {e}"))?;
        Ok(Some(directory.to_string_lossy().into_owned()))
    }).await.map_err(|e| e.to_string())?
}

fn install_checked_file(
    source: &Path,
    target: &Path,
    bytes: u64,
    sha256: &str,
) -> Result<(), String> {
    let metadata = source.metadata().map_err(|e| e.to_string())?;
    if !metadata.is_file() || metadata.len() != bytes {
        return Err(format!(
            "The selected database has {} bytes; expected {bytes}",
            metadata.len()
        ));
    }
    let mut input = File::open(source).map_err(|e| e.to_string())?;
    write_checked_resource(&mut input, target, bytes, sha256, |_| Ok(()))
}

// Hash while streaming to disk: a multi-gigabyte download never lives in RAM
// and only a complete, verified file replaces the installed resource.
fn write_checked_resource(
    input: &mut impl Read,
    target: &Path,
    bytes: u64,
    sha256: &str,
    mut progress: impl FnMut(u64) -> Result<(), String>,
) -> Result<(), String> {
    let mut staged =
        tempfile::NamedTempFile::new_in(target.parent().ok_or("Invalid resource directory")?)
            .map_err(|e| e.to_string())?;
    let mut digest = Sha256::new();
    let mut buffer = vec![0_u8; 1024 * 1024];
    let mut copied = 0_u64;
    loop {
        progress(copied)?;
        let count = input.read(&mut buffer).map_err(|e| e.to_string())?;
        if count == 0 {
            break;
        }
        if copied + count as u64 > bytes {
            return Err("The database exceeds its expected size. Installation stopped.".into());
        }
        staged
            .write_all(&buffer[..count])
            .map_err(|e| e.to_string())?;
        digest.update(&buffer[..count]);
        copied += count as u64;
    }
    let actual = format!("{:x}", digest.finalize());
    if copied != bytes || !actual.eq_ignore_ascii_case(sha256) {
        return Err(
            "The selected database does not match the current Convert-Pheno resource manifest"
                .into(),
        );
    }
    staged.as_file().sync_all().map_err(|e| e.to_string())?;
    staged.persist(target).map_err(|e| e.to_string())?;
    Ok(())
}

#[tauri::command]
async fn install_ohdsi(app: tauri::AppHandle) -> Result<Option<String>, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let Some(selected) = app
            .dialog()
            .file()
            .add_filter("SQLite database", &["db"])
            .blocking_pick_file()
        else {
            return Ok(None);
        };
        let source = selected.into_path().map_err(|e| e.to_string())?;
        let engine = app.state::<Engine>();
        let _guard = engine.resource_install.try_lock()
            .map_err(|_| "A database installation is already running")?;
        let target = engine.resource_dir.lock().map_err(|e| e.to_string())?.join("ohdsi.db");
        install_checked_file(&source, &target, engine.ohdsi_bytes, &engine.ohdsi_sha256)?;
        Ok(Some(target.to_string_lossy().into_owned()))
    })
    .await
    .map_err(|e| e.to_string())?
}

#[derive(Clone, Serialize)]
#[serde(rename_all = "camelCase")]
struct DownloadProgress {
    completed_bytes: u64,
    total_bytes: u64,
}

fn ohdsi_response(url: &str, bytes: u64) -> Result<reqwest::blocking::Response, String> {
    let client = Client::builder().https_only(true)
        .connect_timeout(Duration::from_secs(30))
        .timeout(Duration::from_secs(60))
        .build().map_err(|e| e.to_string())?;
    let response = client.get(url).send()
        .and_then(|r| r.error_for_status())
        .map_err(|e| format!("Could not download OHDSI: {e}. Retry or install from file."))?;
    if response.headers().get(reqwest::header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok()).is_some_and(|v| v.contains("text/html")) {
        return Err("Google Drive returned a web page instead of the database. Retry later or install from file.".into());
    }
    if response.content_length().is_some_and(|size| size != bytes) {
        return Err("The download size differs from the resource manifest. Installation stopped.".into());
    }
    Ok(response)
}

#[tauri::command]
async fn download_ohdsi(
    app: tauri::AppHandle,
    on_progress: tauri::ipc::Channel<DownloadProgress>,
) -> Result<String, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let engine = app.state::<Engine>();
        let _guard = engine.resource_install.try_lock()
            .map_err(|_| "A database installation is already running")?;
        engine.cancel_download.store(false, Ordering::Relaxed);
        let mut response = ohdsi_response(&engine.ohdsi_url, engine.ohdsi_bytes)?;
        let target = engine.resource_dir.lock().map_err(|e| e.to_string())?.join("ohdsi.db");
        let mut last_report = std::time::Instant::now() - Duration::from_secs(1);
        write_checked_resource(&mut response, &target, engine.ohdsi_bytes, &engine.ohdsi_sha256, |bytes| {
            if engine.cancel_download.load(Ordering::Relaxed) {
                return Err("Download cancelled. The installed database was not changed.".into());
            }
            if last_report.elapsed() >= Duration::from_millis(200) || bytes == engine.ohdsi_bytes {
                let _ = on_progress.send(DownloadProgress {
                    completed_bytes: bytes, total_bytes: engine.ohdsi_bytes,
                });
                last_report = std::time::Instant::now();
            }
            Ok(())
        })?;
        Ok(target.to_string_lossy().into_owned())
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
fn cancel_ohdsi_download(engine: tauri::State<Engine>) {
    engine.cancel_download.store(true, Ordering::Relaxed);
}

#[tauri::command]
fn connection(engine: tauri::State<Engine>) -> Connection {
    engine.connection.clone()
}

#[tauri::command]
async fn select_paths(
    app: tauri::AppHandle,
    directory: bool,
    multiple: bool,
) -> Result<Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        let dialog = app.dialog().file();
        let paths = if directory {
            dialog.blocking_pick_folder().map(|p| vec![p])
        } else if multiple {
            dialog.blocking_pick_files()
        } else {
            dialog.blocking_pick_file().map(|p| vec![p])
        };
        let Some(paths) = paths else {
            return Ok(json!([]));
        };
        let paths: Vec<PathBuf> = paths
            .into_iter()
            .map(|p| p.into_path().map_err(|e| e.to_string()))
            .collect::<Result<_, _>>()?;
        let engine = app.state::<Engine>();
        let response = engine
            .client
            .post(format!("{}/api/inputs/local", engine.connection.url))
            .bearer_auth(&engine.connection.token)
            .header("X-Convert-Pheno-Local", &engine.local_token)
            .json(&json!({"paths": paths}))
            .send()
            .map_err(|e| e.to_string())?;
        let mut handles = engine.json(response)?;
        if let Some(items) = handles.as_array_mut() {
            for (item, path) in items.iter_mut().zip(paths.iter()) {
                item["displayPath"] = json!(path.to_string_lossy());
            }
        }
        Ok(handles)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn confirm_action(
    app: tauri::AppHandle,
    title: String,
    message: String,
) -> Result<bool, String> {
    tauri::async_runtime::spawn_blocking(move || {
        app.dialog()
            .message(message)
            .title(title)
            .buttons(tauri_plugin_dialog::MessageDialogButtons::OkCancel)
            .blocking_show()
    })
    .await
    .map_err(|e| e.to_string())
}

#[tauri::command]
async fn project_file(app: tauri::AppHandle, operation: String, handle: Option<String>, data: Option<Value>) -> Result<Value, String> {
    tauri::async_runtime::spawn_blocking(move || {
        if operation != "save" && operation != "open" { return Err("Unknown project operation".into()); }
        let mut body = json!({"data": data});
        if operation == "save" && handle.is_some() {
            body["handle"] = json!(handle);
        } else {
            let dialog = app.dialog().file().add_filter("Convert-Pheno project", &["cpheno"]);
            let selected = if operation == "save" {
                dialog.set_file_name("project.cpheno").blocking_save_file()
            } else { dialog.blocking_pick_file() };
            let Some(selected) = selected else { return Ok(Value::Null) };
            let mut path = selected.into_path().map_err(|e| e.to_string())?;
            if operation == "save" && path.extension().is_none() { path.set_extension("cpheno"); }
            if operation == "open" && !app.dialog().message("Open this project and authorize access to its referenced input files? Only open projects from a trusted source. Original files will not be modified.").title("Open project").buttons(tauri_plugin_dialog::MessageDialogButtons::OkCancel).blocking_show() {
                return Ok(Value::Null);
            }
            body["path"] = json!(path);
        }
        let engine = app.state::<Engine>();
        let response = engine.client.post(format!("{}/api/projects/local/{}", engine.connection.url, operation))
            .bearer_auth(&engine.connection.token).header("X-Convert-Pheno-Local", &engine.local_token)
            // Project-owned example files may be copied to an external drive.
            .timeout(Duration::from_secs(300))
            .json(&body).send().map_err(|e| e.to_string())?;
        engine.json(response)
    }).await.map_err(|e| e.to_string())?
}

#[tauri::command]
fn finish_quit(app: tauri::AppHandle) {
    app.state::<ExitApproval>().0.store(true, Ordering::SeqCst);
    app.exit(0);
}

struct ExitApproval(AtomicBool);

fn open_os(target: &str) -> Result<(), String> {
    #[cfg(target_os = "macos")]
    let result = Command::new("open").arg(target).spawn();
    #[cfg(target_os = "linux")]
    let result = Command::new("xdg-open").arg(target).spawn();
    #[cfg(windows)]
    let result = Command::new("explorer.exe").arg(target).spawn();
    result.map(|_| ()).map_err(|e| e.to_string())
}

#[tauri::command]
fn open_external(url: String) -> Result<(), String> {
    if ![
        "https://cnag-biomedical-informatics.github.io/convert-pheno/",
        "https://cnag-biomedical-informatics.github.io/convert-pheno/terminology-search",
        "https://github.com/CNAG-Biomedical-Informatics/convert-pheno",
        "https://drive.google.com/drive/folders/1-5Ywf-hhwb8bX1sRNV2Tf3EjH4TCaC8P?usp=sharing",
    ]
    .contains(&url.as_str())
    {
        return Err("This external link is not allowed".into());
    }
    open_os(&url)
}

fn valid_id(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= 128
        && id
            .bytes()
            .all(|c| c.is_ascii_alphanumeric() || c == b'-' || c == b'_')
}

#[tauri::command]
async fn reveal_run(app: tauri::AppHandle, id: String) -> Result<(), String> {
    if !valid_id(&id) {
        return Err("Invalid run identifier".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let engine = app.state::<Engine>();
        let response = engine
            .client
            .get(format!("{}/api/jobs/{id}", engine.connection.url))
            .bearer_auth(&engine.connection.token)
            .send()
            .map_err(|e| e.to_string())?;
        let job = engine.json(response)?;
        let path = job["directory"]
            .as_str()
            .ok_or("This run has no output folder")?;
        open_os(path)
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn save_output(
    app: tauri::AppHandle,
    job: String,
    artifact: String,
    filename: String,
) -> Result<(), String> {
    if !valid_id(&job) || !valid_id(&artifact) {
        return Err("Invalid output identifier".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let filename = PathBuf::from(filename)
            .file_name()
            .ok_or("Invalid filename")?
            .to_string_lossy()
            .into_owned();
        let Some(selected) = app
            .dialog()
            .file()
            .set_file_name(filename)
            .blocking_save_file()
        else {
            return Ok(());
        };
        let target = selected.into_path().map_err(|e| e.to_string())?;
        let engine = app.state::<Engine>();
        let mut response = engine
            .client
            .get(format!(
                "{}/api/jobs/{job}/outputs/{artifact}/download",
                engine.connection.url
            ))
            .bearer_auth(&engine.connection.token)
            .timeout(Duration::from_secs(3600))
            .send()
            .map_err(|e| e.to_string())?
            .error_for_status()
            .map_err(|e| e.to_string())?;
        // Stream to a sibling temporary file; a failed download never replaces the destination.
        let mut staged =
            tempfile::NamedTempFile::new_in(target.parent().ok_or("Invalid destination")?)
                .map_err(|e| e.to_string())?;
        response
            .copy_to(staged.as_file_mut())
            .map_err(|e| e.to_string())?;
        staged.as_file().sync_all().map_err(|e| e.to_string())?;
        staged.persist(target).map_err(|e| e.to_string())?;
        Ok(())
    })
    .await
    .map_err(|e| e.to_string())?
}

#[tauri::command]
async fn save_mapping_copy(app: tauri::AppHandle, text: String) -> Result<Option<String>, String> {
    if text.len() > 1048576 {
        return Err("Mapping exceeds the 1 MiB editor limit".into());
    }
    tauri::async_runtime::spawn_blocking(move || {
        let Some(selected) = app
            .dialog()
            .file()
            .set_file_name("mapping-reviewed.yaml")
            .add_filter("YAML mapping", &["yaml", "yml"])
            .blocking_save_file()
        else {
            return Ok(None);
        };
        let target = selected.into_path().map_err(|e| e.to_string())?;
        if target.exists() {
            return Err(
                "Choose a new filename. Save As never overwrites an existing mapping.".into(),
            );
        }
        write_mapping_copy(&target, &text)?;
        Ok(Some(target.to_string_lossy().into_owned()))
    })
    .await
    .map_err(|e| e.to_string())?
}

fn write_mapping_copy(target: &std::path::Path, text: &str) -> Result<(), String> {
    let mut staged = tempfile::NamedTempFile::new_in(target.parent().ok_or("Invalid destination")?)
        .map_err(|e| e.to_string())?;
    staged
        .write_all(text.as_bytes())
        .map_err(|e| e.to_string())?;
    staged.as_file().sync_all().map_err(|e| e.to_string())?;
    // No-clobber protects both original mappings and files created after the dialog.
    staged
        .persist_noclobber(target)
        .map_err(|e| e.to_string())?;
    Ok(())
}

#[cfg(test)]
mod mapping_tests {
    #[test]
    fn resource_directory_settings_survive_restart_and_missing_drives() {
        let dir = tempfile::tempdir().unwrap();
        let config = dir.path().join("settings.json");
        let default = dir.path().join("default");
        assert_eq!(super::read_resource_directory(&config, &default).unwrap(), default);
        let selected = dir.path().join("disconnected-drive");
        std::fs::write(&config, serde_json::to_vec(&serde_json::json!({"directory":selected})).unwrap()).unwrap();
        assert_eq!(super::read_resource_directory(&config, &default).unwrap(), selected);
        std::fs::write(&config, r#"{"directory":"relative"}"#).unwrap();
        assert!(super::read_resource_directory(&config, &default).is_err());
    }
    #[test]
    fn streamed_resources_preserve_existing_files_on_failure() {
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("ohdsi.db");
        std::fs::write(&target, b"previous").unwrap();
        let data = b"new database";
        let hash = format!("{:x}", Sha256::digest(data));
        for bytes in [data.len() as u64 - 1, data.len() as u64 + 1] {
            assert!(super::write_checked_resource(&mut &data[..], &target, bytes, &hash, |_| Ok(())).is_err());
            assert_eq!(std::fs::read(&target).unwrap(), b"previous");
        }
        assert!(super::write_checked_resource(&mut &data[..], &target, data.len() as u64, &"0".repeat(64), |_| Ok(())).is_err());
        assert!(super::write_checked_resource(&mut &data[..], &target, data.len() as u64, &hash, |_| Err("Cancelled".into())).is_err());
        assert_eq!(std::fs::read(&target).unwrap(), b"previous");
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
        let mut progress = vec![];
        super::write_checked_resource(&mut &data[..], &target, data.len() as u64, &hash, |bytes| { progress.push(bytes); Ok(()) }).unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), data);
        assert_eq!(progress.last(), Some(&(data.len() as u64)));
    }

    #[test]
    #[ignore = "Downloads the complete 3.2 GB OHDSI resource from Google Drive"]
    fn live_ohdsi_download() {
        let manifest: serde_json::Value = serde_json::from_str(include_str!("../../../share/db/manifest.json")).unwrap();
        let resource = &manifest["databases"]["ohdsi"];
        let bytes = resource["byteSize"].as_u64().unwrap();
        let mut response = super::ohdsi_response(resource["downloadUrl"].as_str().unwrap(), bytes).unwrap();
        let dir = tempfile::tempdir().unwrap();
        let target = dir.path().join("ohdsi.db");
        let mut last = 0;
        super::write_checked_resource(&mut response, &target, bytes, resource["sha256"].as_str().unwrap(), |received| {
            let percent = received * 100 / bytes;
            if percent >= last + 10 { eprintln!("OHDSI download: {percent}%"); last = percent; }
            Ok(())
        }).unwrap();
        assert_eq!(std::fs::metadata(target).unwrap().len(), bytes);
    }

    use super::{install_checked_file, write_mapping_copy};
    use sha2::{Digest, Sha256};
    #[test]
    fn save_copy_preserves_existing_files() {
        let dir = tempfile::tempdir().unwrap();
        let file = dir.path().join("mapping.yaml");
        write_mapping_copy(&file, "mappingVersion: 2\n").unwrap();
        assert_eq!(
            std::fs::read_to_string(&file).unwrap(),
            "mappingVersion: 2\n"
        );
        assert!(write_mapping_copy(&file, "replaced").is_err());
        assert_eq!(
            std::fs::read_to_string(&file).unwrap(),
            "mappingVersion: 2\n"
        );
        assert_eq!(std::fs::read_dir(dir.path()).unwrap().count(), 1);
    }

    #[test]
    fn external_resource_is_verified_before_replacement() {
        let dir = tempfile::tempdir().unwrap();
        let source = dir.path().join("download.db");
        let target = dir.path().join("ohdsi.db");
        std::fs::write(&source, b"synthetic database").unwrap();
        let hash = format!("{:x}", Sha256::digest(b"synthetic database"));
        install_checked_file(&source, &target, 18, &hash).unwrap();
        assert_eq!(std::fs::read(&target).unwrap(), b"synthetic database");
        assert!(install_checked_file(&source, &target, 18, &"0".repeat(64)).is_err());
        assert_eq!(std::fs::read(&target).unwrap(), b"synthetic database");
    }
}

fn menus(app: &tauri::App) -> tauri::Result<Menu<tauri::Wry>> {
    let action = |id, label, shortcut| MenuItem::with_id(app, id, label, true, shortcut);
    let about = action("about", "About Convert-Pheno", None)?;
    let settings = action("settings", "Settings...", Some("CmdOrCtrl+,"))?;
    let file = Submenu::with_items(
        app,
        "File",
        true,
        &[
            &action("new", "New Project", Some("CmdOrCtrl+N"))?,
            &action("open", "Open Project...", Some("CmdOrCtrl+O"))?,
            &action("save", "Save Project", Some("CmdOrCtrl+S"))?,
            &action("save-as", "Save Project As...", Some("CmdOrCtrl+Shift+S"))?,
            &action("close-project", "Close Project", None::<&str>)?,
            &PredefinedMenuItem::separator(app)?,
            &action("add", "Add Input...", Some("CmdOrCtrl+I"))?,
            &PredefinedMenuItem::close_window(app, None)?,
        ],
    )?;
    let edit = Submenu::with_items(
        app,
        "Edit",
        true,
        &[
            &PredefinedMenuItem::undo(app, None)?,
            &PredefinedMenuItem::redo(app, None)?,
            &PredefinedMenuItem::separator(app)?,
            &PredefinedMenuItem::cut(app, None)?,
            &PredefinedMenuItem::copy(app, None)?,
            &PredefinedMenuItem::paste(app, None)?,
            &PredefinedMenuItem::select_all(app, None)?,
        ],
    )?;
    let view = Submenu::with_items(
        app,
        "View",
        true,
        &[
            &action("explorer", "Toggle Explorer", None)?,
            &action("inspector", "Toggle Inspector", None)?,
            &action("tasks", "Toggle Tasks", None)?,
            &action("resources", "Terminology Resources", None)?,
            &PredefinedMenuItem::fullscreen(app, None)?,
        ],
    )?;
    let conversion = Submenu::with_items(
        app,
        "Conversion",
        true,
        &[&action("run", "Run Conversion", Some("CmdOrCtrl+Enter"))?],
    )?;
    let runs = Submenu::with_items(
        app,
        "Runs",
        true,
        &[
            &action("cancel", "Cancel Active Run...", None)?,
            &action("cancel-pending", "Cancel Pending Runs...", None)?,
            &PredefinedMenuItem::separator(app)?,
            &action(
                "delete-history",
                "Delete All Finished Runs from History...",
                None,
            )?,
            &action("delete-files", "Delete All Finished Run Files...", None)?,
        ],
    )?;
    let help = Submenu::with_items(
        app,
        "Help",
        true,
        &[
            &action("docs", "Documentation", None)?,
            &action("github", "GitHub Repository", None)?,
            &action("updates", "Check for Updates...", None)?,
        ],
    )?;
    #[cfg(target_os = "macos")]
    {
        let application = Submenu::with_items(
            app,
            "Convert-Pheno",
            true,
            &[
                &about,
                &settings,
                &PredefinedMenuItem::separator(app)?,
                &PredefinedMenuItem::services(app, None)?,
                &PredefinedMenuItem::hide(app, None)?,
                &PredefinedMenuItem::hide_others(app, None)?,
                &PredefinedMenuItem::show_all(app, None)?,
                &PredefinedMenuItem::quit(app, None)?,
            ],
        )?;
        Menu::with_items(
            app,
            &[&application, &file, &edit, &view, &conversion, &runs, &help],
        )
    }
    #[cfg(not(target_os = "macos"))]
    {
        edit.append(&settings)?;
        help.append(&about)?;
        file.append(&PredefinedMenuItem::quit(app, None)?)?;
        Menu::with_items(app, &[&file, &edit, &view, &conversion, &runs, &help])
    }
}

fn main() {
    #[cfg(target_os = "linux")]
    if !Path::new("/dev/dri").exists()
        && std::env::var_os("WEBKIT_DISABLE_COMPOSITING_MODE").is_none()
    {
        // Avoid WebKitGTK's EGL/DRI3 probe on software-only virtual machines.
        std::env::set_var("WEBKIT_DISABLE_COMPOSITING_MODE", "1");
    }
    let app = tauri::Builder::default()
        .plugin(tauri_plugin_dialog::init())
        .plugin(tauri_plugin_clipboard_manager::init())
        .setup(|app| {
            app.manage(ExitApproval(AtomicBool::new(false)));
            app.manage(start_engine(app)?);
            app.set_menu(menus(app)?)?;
            // Exercise the packaged application and its real startup hook in CI.
            if std::env::var_os("CONVERT_PHENO_DESKTOP_SMOKE_TEST").is_some() {
                println!("Desktop startup smoke test passed");
                app.handle().exit(0);
            }
            Ok(())
        })
        .on_menu_event(|app, event| {
            if matches!(event.id().as_ref(), "about" | "updates") {
                let app = app.clone();
                let update = event.id().as_ref() == "updates";
                tauri::async_runtime::spawn_blocking(move || {
                    let message = if update {
                        release_check::check(env!("CARGO_PKG_VERSION"))
                            .unwrap_or_else(|error| format!("Could not check for updates. {error}\n\nTry again later or visit the GitHub repository from Help."))
                    } else {
                        format!(concat!(
                            "Convert-Pheno\nDesktop version {}\n\n",
                            "Clinical and phenotypic data conversion\n\n",
                            "Components\n",
                            "Tauri (Rust) - native desktop integration\n",
                            "React - user interface\n",
                            "Convert-Pheno - core conversion engine\n",
                            "Mojolicious - local API service\n",
                            "SQLite - terminology databases\n",
                            "CodeMirror - mapping editor\n",
                            "Lucide - interface icons\n",
                            "Papa Parse - CSV previews\n",
                            "fflate - ZIP handling\n\n",
                            "Built with TypeScript and Vite\n\n",
                            "Manuel Rueda\nCNAG\nArtistic License 2.0\n",
                            "Third-party components retain their own licenses."
                        ), env!("CARGO_PKG_VERSION"))
                    };
                    app.dialog().message(message).title(if update { "Convert-Pheno updates" } else { "About Convert-Pheno" }).blocking_show();
                });
                return;
            }
            let _ = app.emit("desktop-menu", event.id().as_ref());
        })
        .on_window_event(|window, event| {
            if let tauri::WindowEvent::CloseRequested { api, .. } = event {
                if !window.state::<ExitApproval>().0.load(Ordering::SeqCst) {
                    api.prevent_close();
                    let _ = window.emit("desktop-menu", "quit");
                }
            }
        })
        .invoke_handler(tauri::generate_handler![
            project_file,
            finish_quit,
            confirm_action,
            connection,
            select_paths,
            open_external,
            reveal_run,
            save_output,
            save_mapping_copy,
            install_ohdsi,
            download_ohdsi,
            cancel_ohdsi_download,
            resource_directory,
            choose_resource_directory
        ])
        .build(tauri::generate_context!())
        .expect("Could not start Convert-Pheno desktop");
    app.run(|app, event| {
        if let tauri::RunEvent::ExitRequested { api, .. } = &event {
            if std::env::var_os("CONVERT_PHENO_DESKTOP_SMOKE_TEST").is_none() && !app.state::<ExitApproval>().0.load(Ordering::SeqCst) {
                api.prevent_exit();
                let _ = app.emit("desktop-menu", "quit");
            }
        }
        if let tauri::RunEvent::Exit = event {
            app.state::<Engine>().stop();
        }
    });
}
