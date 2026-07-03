import os
import re

def migrate_file(filepath):
    with open(filepath, 'r', encoding='utf-8') as f:
        content = f.read()
    
    # 1. Migrate withOpacity(val) to withValues(alpha: val)
    # We need to be careful with constant expressions
    # This script will just do the basic replacement and then I'll fix const manually if needed
    new_content = re.sub(r'\.withOpacity\(([^)]+)\)', r'.withValues(alpha: \1)', content)
    
    if new_content != content:
        with open(filepath, 'w', encoding='utf-8') as f:
            f.write(new_content)
        print(f"Migrated: {filepath}")

# List of files from grep results
files = [
    r"e:\Development\NightView\lunara_app\lib\widgets\neon_waves_background.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\phone_mockup.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\match_card.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\logo_animator.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\in_app_alerts.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\flowing_ribbons.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\cinematic_logo_reveal.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\animated_neon_lines.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\angular_neon_lines.dart",
    r"e:\Development\NightView\lunara_app\lib\widgets\action_button.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\discovery\venue_reviews_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\social\icebreaker_modal.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\social\match_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\social\match_success_dialog.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\social\swipe_intro_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\social\venue_invite_picker_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\discovery\discovery_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\profile_setup\profile_vibe_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\profile_setup\profile_privacy_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\profile\profile_hub_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\profile_setup\profile_photos_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\profile\points_rewards_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\post_booking\ticket_pocket_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\auth\phone_login_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\auth\reset_success_screen.dart",
    # Re-adding some that might have missed lines
    r"e:\Development\NightView\lunara_app\lib\screens\discovery\venue_detail_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\discovery\guestlist_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\discovery\digital_ticket_screen.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\home\home_tab.dart",
    r"e:\Development\NightView\lunara_app\lib\screens\home\dashboard.dart",
]

for f in files:
    if os.path.exists(f):
        migrate_file(f)
    else:
        print(f"Not found: {f}")
