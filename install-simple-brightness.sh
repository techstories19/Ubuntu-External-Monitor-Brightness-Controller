#!/bin/bash
# Installation script for Simple System Tray Brightness Controller

echo "Installing Simple System Tray Brightness Controller..."

# Ensure required dependencies are installed
echo "Installing dependencies..."
sudo apt update
sudo apt install -y python3-gi gir1.2-gtk-3.0 x11-xserver-utils gir1.2-appindicator3-0.1

# Create application directory
APP_DIR="$HOME/.local/share/simple-brightness-controller"
mkdir -p "$APP_DIR"

# Create desktop entry directory if it doesn't exist
mkdir -p "$HOME/.local/share/applications"

# Save the main script
echo "Creating application file..."
cat > "$APP_DIR/simple_brightness.py" << 'EOF'
#!/usr/bin/env python3
"""
SimpleXrandrBrightness - A minimal system tray tool for adjusting monitor brightness with xrandr.
"""

import gi
import os
import signal
import subprocess
import json
from pathlib import Path

# Ensure required versions
gi.require_version('Gtk', '3.0')
gi.require_version('AppIndicator3', '0.1')

from gi.repository import Gtk, AppIndicator3, GLib

# Configuration file for saving settings
CONFIG_FILE = Path.home() / '.config' / 'simple-brightness.json'

class SimpleXrandrBrightness:
    def __init__(self):
        self.monitors = []
        self.brightness_values = {}
        self.minimum_brightness = 0.1  # Minimum 10% brightness to prevent black screen
        
        # Load saved brightness values
        self.load_config()
        
        # Detect monitors
        self.detect_monitors()
        
        # Create indicator
        self.indicator = AppIndicator3.Indicator.new(
            "simple-brightness-controller",
            "display-brightness-symbolic",  # Icon name
            AppIndicator3.IndicatorCategory.APPLICATION_STATUS
        )
        self.indicator.set_status(AppIndicator3.IndicatorStatus.ACTIVE)
        
        # Create menu
        self.build_menu()
        
        # Set up signals
        signal.signal(signal.SIGINT, self.quit)
        signal.signal(signal.SIGTERM, self.quit)
    
    def detect_monitors(self):
        """Detect connected monitors using xrandr"""
        try:
            output = subprocess.check_output(['xrandr', '--query']).decode('utf-8')
            for line in output.splitlines():
                if " connected" in line:
                    # Extract monitor name (first word in the line)
                    monitor_name = line.split()[0]
                    self.monitors.append(monitor_name)
                    
                    # Initialize with saved brightness or default
                    if monitor_name not in self.brightness_values:
                        self.brightness_values[monitor_name] = 1.0
        except Exception as e:
            print(f"Error detecting monitors: {e}")
    
    def load_config(self):
        """Load saved brightness settings"""
        if CONFIG_FILE.exists():
            try:
                with open(CONFIG_FILE, 'r') as f:
                    self.brightness_values = json.load(f)
            except Exception as e:
                print(f"Error loading config: {e}")
                self.brightness_values = {}
    
    def save_config(self):
        """Save brightness settings"""
        CONFIG_FILE.parent.mkdir(parents=True, exist_ok=True)
        try:
            with open(CONFIG_FILE, 'w') as f:
                json.dump(self.brightness_values, f)
        except Exception as e:
            print(f"Error saving config: {e}")
    
    def apply_brightness(self, monitor, brightness):
        """Apply brightness to a monitor using xrandr"""
        try:
            # Ensure brightness is not below minimum
            brightness = max(brightness, self.minimum_brightness)
            
            subprocess.run(['xrandr', '--output', monitor, '--brightness', str(brightness)])
            self.brightness_values[monitor] = brightness
            return True
        except Exception as e:
            print(f"Error applying brightness to {monitor}: {e}")
            return False
    
    def apply_to_all_monitors(self, brightness):
        """Apply brightness to all connected monitors"""
        for monitor in self.monitors:
            self.apply_brightness(monitor, brightness)
        self.save_config()
    
    def build_menu(self):
        """Build the indicator menu"""
        menu = Gtk.Menu()
        
        # Monitor submenu
        if len(self.monitors) > 1:
            monitor_item = Gtk.MenuItem(label="Select Monitor")
            monitor_submenu = Gtk.Menu()
            
            # Add menu items for individual monitors
            for monitor in self.monitors:
                monitor_submenu_item = Gtk.MenuItem(label=monitor)
                monitor_submenu_item.connect("activate", self.on_monitor_selected, monitor)
                monitor_submenu.append(monitor_submenu_item)
            
            monitor_item.set_submenu(monitor_submenu)
            menu.append(monitor_item)
            
            # Separator
            menu.append(Gtk.SeparatorMenuItem())
        
        # All monitors label
        all_monitors_label = Gtk.MenuItem(label="All Monitors")
        all_monitors_label.set_sensitive(False)
        menu.append(all_monitors_label)
        
        # Brightness presets for all monitors
        brightness_100 = Gtk.MenuItem(label="Brightness: 100%")
        brightness_100.connect("activate", self.on_brightness_preset, 1.0)
        menu.append(brightness_100)
        
        brightness_75 = Gtk.MenuItem(label="Brightness: 75%")
        brightness_75.connect("activate", self.on_brightness_preset, 0.75)
        menu.append(brightness_75)
        
        brightness_50 = Gtk.MenuItem(label="Brightness: 50%")
        brightness_50.connect("activate", self.on_brightness_preset, 0.5)
        menu.append(brightness_50)
        
        brightness_25 = Gtk.MenuItem(label="Brightness: 25%")
        brightness_25.connect("activate", self.on_brightness_preset, 0.25)
        menu.append(brightness_25)
        
        # Separator
        menu.append(Gtk.SeparatorMenuItem())
        
        # Refresh monitors
        refresh_item = Gtk.MenuItem(label="Refresh Monitors")
        refresh_item.connect("activate", self.on_refresh)
        menu.append(refresh_item)
        
        # Quit
        menu.append(Gtk.SeparatorMenuItem())
        quit_item = Gtk.MenuItem(label="Quit")
        quit_item.connect("activate", self.quit)
        menu.append(quit_item)
        
        menu.show_all()
        self.indicator.set_menu(menu)
    
    def on_monitor_selected(self, widget, monitor):
        """When a monitor is selected from the submenu"""
        # Create a window with a brightness slider for the selected monitor
        dialog = Gtk.Dialog(
            title=f"Adjust {monitor} Brightness",
            flags=0
        )
        dialog.add_button("Close", Gtk.ResponseType.CLOSE)
        dialog.set_default_size(300, 100)
        
        box = dialog.get_content_area()
        box.set_border_width(10)
        
        # Get current brightness
        current_brightness = self.brightness_values.get(monitor, 1.0)
        
        # Create slider
        scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, self.minimum_brightness, 1.0, 0.05)
        scale.set_value(current_brightness)
        scale.set_digits(2)
        scale.set_hexpand(True)
        scale.connect("value-changed", self.on_single_monitor_brightness_changed, monitor)
        
        box.add(scale)
        dialog.show_all()
        
        dialog.run()
        dialog.destroy()
    
    def on_single_monitor_brightness_changed(self, scale, monitor):
        """Handle brightness change for a single monitor"""
        brightness = scale.get_value()
        self.apply_brightness(monitor, brightness)
        self.save_config()
    
    def on_brightness_preset(self, widget, brightness):
        """Handle brightness preset selection"""
        self.apply_to_all_monitors(brightness)
    
    def on_refresh(self, widget):
        """Refresh the list of monitors"""
        self.monitors = []
        self.detect_monitors()
        self.build_menu()
    
    def run(self):
        """Run the application"""
        # Apply saved brightness values on startup
        for monitor, brightness in self.brightness_values.items():
            if monitor in self.monitors:
                self.apply_brightness(monitor, brightness)
        
        # Run the main loop
        Gtk.main()
    
    def quit(self, *args):
        """Quit the application"""
        self.save_config()
        Gtk.main_quit()

if __name__ == "__main__":
    app = SimpleXrandrBrightness()
    app.run()
EOF

# Make application executable
chmod +x "$APP_DIR/simple_brightness.py"

# Create desktop entry for application launcher
cat > "$HOME/.local/share/applications/simple-brightness-controller.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Simple Brightness Controller
Comment=Simple system tray tool for monitor brightness
Exec=$APP_DIR/simple_brightness.py
Icon=display-brightness
Terminal=false
Categories=Utility;Settings;
Keywords=brightness;monitor;display;
EOF

# Create autostart entry
mkdir -p "$HOME/.config/autostart"
cat > "$HOME/.config/autostart/simple-brightness-controller.desktop" << EOF
[Desktop Entry]
Version=1.0
Type=Application
Name=Simple Brightness Controller
Comment=Simple system tray tool for monitor brightness
Exec=$APP_DIR/simple_brightness.py
Icon=display-brightness
Terminal=false
Categories=Utility;Settings;
Keywords=brightness;monitor;display;
X-GNOME-Autostart-enabled=true
EOF

echo "Installation complete!"
echo "You can now launch Simple Brightness Controller from your application menu"
echo "or by running: $APP_DIR/simple_brightness.py"
echo "The application will also start automatically when you log in."
echo ""
echo "To disable autostart, delete the file:"
echo "$HOME/.config/autostart/simple-brightness-controller.desktop"
