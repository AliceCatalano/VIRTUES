from pathlib import Path
import shutil

# --- HARDCODED PATHS ---
SOURCE_BASE = Path("/run/user/1002/gvfs/smb-share:server=shark,share=acatalano/subject_s01H")
DEST_BASE = Path("/run/user/1002/gvfs/smb-share:server=shark,share=acatalano/subject_s01H/videos/Baseline1")

# Ensure destination exists
DEST_BASE.mkdir(parents=True, exist_ok=True)

# Iterate over all rep_* folders
for rep_dir in SOURCE_BASE.glob("Level*"):
    if not rep_dir.is_dir():
        continue

    rep_name = rep_dir.name          # e.g., "rep_3"
    rep_number = rep_name.split("_")[-1]  # extract "3"

    video_bag_path = rep_dir / "video_bag"

    if video_bag_path.exists() and video_bag_path.is_dir():
        new_name = f"video_bag_{rep_number}"
        temp_renamed_path = rep_dir / new_name

        # Rename inside the rep folder
        video_bag_path.rename(temp_renamed_path)

        # Move to destination
        final_destination = DEST_BASE / new_name
        shutil.move(str(temp_renamed_path), str(final_destination))

        print(f"Moved: {temp_renamed_path} -> {final_destination}")
    else:
        print(f"Skipped (no video_bag): {rep_dir}")