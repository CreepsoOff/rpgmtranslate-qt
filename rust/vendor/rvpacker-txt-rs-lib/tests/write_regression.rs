use rvpacker_txt_rs_lib::{EngineType, FileFlags, WriterBuilder};
use std::{
    error::Error,
    fs::{create_dir_all, read_to_string, write},
    path::{Path, PathBuf},
    process,
    time::{SystemTime, UNIX_EPOCH},
};

fn unique_test_root(name: &str) -> Result<PathBuf, Box<dyn Error>> {
    let now = SystemTime::now().duration_since(UNIX_EPOCH)?.as_nanos();
    let root = std::env::temp_dir().join(format!(
        "rvpacker_write_regression_{name}_{}_{}",
        process::id(),
        now
    ));

    create_dir_all(&root)?;
    Ok(root)
}

fn setup_dirs(root: &Path) -> Result<(PathBuf, PathBuf, PathBuf), Box<dyn Error>> {
    let source = root.join("source").join("data");
    let translation = root.join("translation");
    let output = root.join("output");

    create_dir_all(&source)?;
    create_dir_all(&translation)?;
    create_dir_all(&output)?;

    Ok((source, translation, output))
}

#[test]
fn write_only_when_actor_translation_changes_content() -> Result<(), Box<dyn Error>> {
    let root = unique_test_root("actors_changed")?;
    let (source, translation, output) = setup_dirs(&root)?;

    write(
        source.join("Actors.json"),
        r#"[null,{"id":1,"name":"Hero"}]"#,
    )?;
    write(
        translation.join("actors.txt"),
        "<!-- ID --><#>1\nHero<#>Heros\n",
    )?;

    let mut writer = WriterBuilder::new().with_files(FileFlags::Actors).build();
    writer.write(&source, &translation, &output, EngineType::New)?;

    let output_file = output.join("data").join("Actors.json");
    assert!(output_file.exists(), "Actors.json should be generated when translated entries are present.");

    let content = read_to_string(output_file)?;
    assert!(content.contains("\"Heros\""));

    Ok(())
}

#[test]
fn write_skips_actor_file_when_no_effective_translation() -> Result<(), Box<dyn Error>> {
    let root = unique_test_root("actors_no_translation")?;
    let (source, translation, output) = setup_dirs(&root)?;

    write(
        source.join("Actors.json"),
        r#"[null,{"id":1,"name":"Hero"}]"#,
    )?;
    write(
        translation.join("actors.txt"),
        "<!-- ID --><#>1\nHero<#>\n",
    )?;

    let mut writer = WriterBuilder::new().with_files(FileFlags::Actors).build();
    writer.write(&source, &translation, &output, EngineType::New)?;

    let output_file = output.join("data").join("Actors.json");
    assert!(
        !output_file.exists(),
        "Actors.json should not be generated when no translation value is provided."
    );

    Ok(())
}

#[test]
fn write_system_legacy_unsectioned_lines_is_applied() -> Result<(), Box<dyn Error>> {
    let root = unique_test_root("system_legacy")?;
    let (source, translation, output) = setup_dirs(&root)?;

    write(
        source.join("System.json"),
        r#"{
  "armorTypes":[""],
  "elements":[""],
  "skillTypes":[""],
  "weaponTypes":[""],
  "equipTypes":[""],
  "terms":{
    "basic":[""],
    "commands":["Fight","Escape"],
    "params":[""],
    "messages":{"victory":"You win!"}
  },
  "currencyUnit":"G",
  "gameTitle":"My Game"
}"#,
    )?;
    write(
        translation.join("system.txt"),
        "Fight<#>Combat\nEscape<#>Fuite\nYou win!<#>Tu gagnes !\n",
    )?;

    let mut writer = WriterBuilder::new().with_files(FileFlags::System).build();
    writer.write(&source, &translation, &output, EngineType::New)?;

    let output_file = output.join("data").join("System.json");
    assert!(
        output_file.exists(),
        "System.json should be generated when legacy unsectioned translations are present."
    );

    let content = read_to_string(output_file)?;
    assert!(content.contains("\"Combat\""));
    assert!(content.contains("\"Fuite\""));
    assert!(content.contains("\"Tu gagnes !\""));

    Ok(())
}
