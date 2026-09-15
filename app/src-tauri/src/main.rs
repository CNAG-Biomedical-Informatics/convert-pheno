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
    sync::Mutex,
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
    resource_dir: PathBuf,
    ohdsi_bytes: u64,
    ohdsi_sha256: String,
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
    let resource_dir = app_data.join("resources");
    std::fs::create_dir_all(&state)?;
    std::fs::create_dir_all(&resource_dir)?;
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
    let bundled_ohdsi_dir = root
        .join("share/db")
        .join(manifest["currentBundle"].as_str().unwrap_or("v0"));
    let ohdsi_dir = if cfg!(debug_assertions) && bundled_ohdsi_dir.join("ohdsi.db").is_file() {
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
        #[cfg(target_os = "macos")]
        command.env("DYLD_LIBRARY_PATH", root.join("runtime/lib"));
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
        .env(
            "CONVERT_PHENO_API_ORIGINS",
            "tauri://localhost,http://tauri.localhost,https://tauri.localhost",
        )
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
        resource_dir,
        ohdsi_bytes,
        ohdsi_sha256,
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
        if engine.child.lock().unwrap().try_wait()?.is_some() {
            let details = std::fs::read_to_string(&log_path).unwrap_or_default();
            let details = details.trim();
            return Err(if details.is_empty() {
                "The Perl engine exited during startup without diagnostic output.".into()
            } else {
                format!("The Perl engine exited during startup: {details}").into()
            });
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    Err("The conversion engine did not become ready".into())
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
    let mut staged =
        tempfile::NamedTempFile::new_in(target.parent().ok_or("Invalid resource directory")?)
            .map_err(|e| e.to_string())?;
    let mut digest = Sha256::new();
    let mut buffer = vec![0_u8; 1024 * 1024];
    let mut copied = 0_u64;
    loop {
        let count = input.read(&mut buffer).map_err(|e| e.to_string())?;
        if count == 0 {
            break;
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
    if target.exists() {
        std::fs::remove_file(target).map_err(|e| e.to_string())?;
    }
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
        let target = engine.resource_dir.join("ohdsi.db");
        install_checked_file(&source, &target, engine.ohdsi_bytes, &engine.ohdsi_sha256)?;
        Ok(Some(target.to_string_lossy().into_owned()))
    })
    .await
    .map_err(|e| e.to_string())?
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
            &action("new", "New Workspace", Some("CmdOrCtrl+N"))?,
            &action("open", "Open Workspace...", Some("CmdOrCtrl+O"))?,
            &action("save", "Save Workspace...", Some("CmdOrCtrl+S"))?,
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
        .setup(|app| {
            app.manage(start_engine(app)?);
            app.set_menu(menus(app)?)?;
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
                        format!("Convert-Pheno\nDesktop version {}\n\nClinical and phenotypic data conversion\nPerl conversion engine with a native desktop interface\n\nManuel Rueda\nCNAG\nArtistic License 2.0", env!("CARGO_PKG_VERSION"))
                    };
                    app.dialog().message(message).title(if update { "Convert-Pheno updates" } else { "About Convert-Pheno" }).blocking_show();
                });
                return;
            }
            let _ = app.emit("desktop-menu", event.id().as_ref());
        })
        .invoke_handler(tauri::generate_handler![
            confirm_action,
            connection,
            select_paths,
            open_external,
            reveal_run,
            save_output,
            save_mapping_copy,
            install_ohdsi
        ])
        .build(tauri::generate_context!())
        .expect("Could not start Convert-Pheno desktop");
    app.run(|app, event| {
        if let tauri::RunEvent::Exit = event {
            app.state::<Engine>().stop();
        }
    });
}
