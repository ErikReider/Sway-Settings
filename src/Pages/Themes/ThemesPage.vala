using Gee;

namespace SwaySettings {
    public class ThemesPage : PageScroll {
        ThemesPageContent content = new ThemesPageContent ();

        public ThemesPage (SettingsItem item, Hdy.Deck deck) {
            base (item, deck);
        }

        public override async void on_back (Hdy.Deck deck) {
            content.on_back ();
        }

        public override Gtk.Widget set_child () {
            return content;
        }
    }

    [GtkTemplate (ui = "/org/erikreider/swaysettings/Pages/Themes/ThemesPage.ui")]
    private class ThemesPageContent : Gtk.Box {
        private static Settings settings = new Settings ("org.gnome.desktop.interface");

        [GtkChild]
        private unowned Gtk.Box style_box;

        [GtkChild]
        private unowned Gtk.Box preferences_box;

        private const string DEFAULT_THEME = "Adwaita";

        ThemePreviewItem preview_default = new ThemePreviewItem (ThemeStyle.DEFAULT);
        ThemePreviewItem preview_dark = new ThemePreviewItem (ThemeStyle.DARK);

        ulong self_settings_handler = 0;

        public ThemesPageContent () {
            // Refresh all of the widgets when a value changes
            // This also gets called when ex gnome-tweaks changes a value
            settings.changed.connect ((s, str) => settings_changed (s, str));
            self_settings_handler = self_settings.changed.connect ((s, str) => {
                settings_changed (s, str);
            });

            style_box.add (preview_default);
            // Links the buttons so that only one button can be active
            preview_dark.set_group (preview_default.group);
            style_box.add (preview_dark);

            set_style_from_settings ();

            preview_default.toggled.connect (style_toggled);
            preview_dark.toggled.connect (style_toggled);

            preferences_box.add (get_preferences ());

            sync_gtk_theme ();
        }

        public void on_back () {
            if (self_settings_handler != 0) {
                self_settings.disconnect (self_settings_handler);
                self_settings_handler = 0;
            }
        }

        private void sync_gtk_theme () {
            string ? theme = get_theme_for_style ();
            string ? applied_theme = Functions.get_gsetting (
                settings,
                "gtk-theme",
                VariantType.STRING)?.get_string ();
            if (theme == null || theme.length == 0) {
                theme = DEFAULT_THEME;
                set_self_theme (theme);
            } else if (theme == applied_theme) return;

            set_gtk_value ("gtk-theme", theme);
        }

        private void set_self_theme (string theme) {
            ThemeStyle style = get_color_scheme ();
            string name = style == ThemeStyle.DARK
                ? Constants.SETTINGS_THEME_DARK : Constants.SETTINGS_THEME_LIGHT;
            Functions.set_gsetting (self_settings, name, theme);
        }

        private string ? get_theme_for_style () {
            ThemeStyle style = get_color_scheme ();
            string name = style == ThemeStyle.DARK
                ? Constants.SETTINGS_THEME_DARK : Constants.SETTINGS_THEME_LIGHT;
            return Functions.get_gsetting (self_settings,
                                           name,
                                           VariantType.STRING) ? .get_string ();
        }

        private void settings_changed (Settings settings, string str) {
            switch (str) {
                case "color-scheme":
                    set_style_from_settings ();
                    break;
                case Constants.SETTINGS_THEME_DARK:
                case Constants.SETTINGS_THEME_LIGHT:
                case "gtk-theme":
                case "icon-theme":
                case "cursor-theme":
                case "enable-animations":
                    foreach (var child in preferences_box.get_children ()) {
                        if (child != null) preferences_box.remove (child);
                    }
                    preferences_box.add (get_preferences ());
                    break;
            }
        }

        private ThemeStyle get_color_scheme () {
            string value = settings.get_string ("color-scheme");
            return ThemeStyle.from_gsettings (value);
        }

        private void set_style_from_settings () {
            bool is_dark = get_color_scheme () == ThemeStyle.DARK;
            ThemePreviewItem previewer = is_dark ? preview_dark : preview_default;

            previewer.toggled.disconnect (style_toggled);
            previewer.set_toggled (true);
            previewer.toggled.connect (style_toggled);

            sync_gtk_theme ();
        }

        private void style_toggled (ThemeStyle style) {
            set_gtk_value ("color-scheme", style.get_gsettings_name (), false);
        }

        private Hdy.PreferencesGroup get_preferences () {
            Hdy.PreferencesGroup pref_group = new Hdy.PreferencesGroup ();
            pref_group.set_title ("GTK Options");

            pref_group.add (
                gtk_theme ("Application Theme", "gtk-theme", "themes"));
            pref_group.add (
                gtk_theme ("Icon Theme", "icon-theme", "icons"));
            pref_group.add (
                gtk_theme ("Cursor Theme", "cursor-theme", "icons"));
            // Animations
            pref_group.add (gtk_animations ());

            pref_group.show_all ();
            return pref_group;
        }

        private Gtk.Widget gtk_animations () {
            string setting_name = "enable-animations";

            var row = new Hdy.ActionRow ();
            row.set_title ("Animations");

            SettingsSchema schema = settings.settings_schema;
            if (!schema.has_key (setting_name)) {
                row.set_sensitive (false);
                return row;
            }

            VariantType type = schema.get_key (setting_name).get_value_type ();
            if (!type.equal (VariantType.BOOLEAN)) {
                row.set_sensitive (false);
                return row;
            }

            bool settings_value = settings.get_boolean (setting_name);
            Gtk.Switch widget = new Gtk.Switch () {
                valign = Gtk.Align.CENTER,
                halign = Gtk.Align.CENTER,
            };
            widget.set_active (settings_value);
            widget.notify["active"].connect (() => {
                set_gtk_value (setting_name, widget.active);
            });

            row.child = widget;
            row.set_activatable_widget (widget);
            row.set_activatable (true);
            return row;
        }

        private Hdy.ComboRow gtk_theme (string title,
                                        string setting_name,
                                        string folder_name) {
            var combo_row = new Hdy.ComboRow ();
            combo_row.set_title (title);

            ListStore liststore = new ListStore (typeof (Hdy.ValueObject));
            string ? current_theme = get_current_gtk_theme (setting_name);
            ArrayList<string> themes = get_gtk_themes (setting_name,
                                                       folder_name);
            if (current_theme == null
                || themes.size == 0
                || !settings.settings_schema.has_key (setting_name)) {
                combo_row.set_sensitive (false);
                return combo_row;
            }
            int selected_index = 0;
            for (int i = 0; i < themes.size; i++) {
                var theme_name = themes[i];
                liststore.append (new Hdy.ValueObject (theme_name));
                if (current_theme == theme_name) selected_index = i;
            }

            combo_row.bind_name_model ((ListModel) liststore, (item) => {
                return ((Hdy.ValueObject) item).get_string ();
            });
            combo_row.set_selected_index (selected_index);
            combo_row.notify["selected-index"].connect (
                (sender, property) => {
                string theme = themes.get (((Hdy.ComboRow) sender)
                                            .get_selected_index ());
                set_self_theme (theme);
                set_gtk_value (setting_name, theme);
            });
            return combo_row;
        }

        void set_gtk_value (string type, Variant val, bool write_file = true) {
            string ? theme_value = Functions.set_gsetting (settings, type, val);
            if (theme_value == null || !write_file) return;

            string ? looking_for = null;
            switch (type) {
                case "gtk-theme":
                    looking_for = "gtk-theme-name";
                    break;
                case "icon-theme":
                    looking_for = "gtk-icon-theme-name";
                    break;
                case "cursor-theme":
                    looking_for = "gtk-cursor-theme-name";
                    break;
                case "enable-animations":
                    looking_for = "gtk-enable-animations";
                    break;
            }
            if (looking_for == null) {
                stderr.printf ("Set GTK Theme error: Settings key not supported!\n");
                return;
            }

            // Also set the .config/gtk-X.0/settings.ini
            // (Firefox ignores the gsettings variable)
            string cfg_dir = Environment.get_user_config_dir ();
            string[] paths = {
                Path.build_filename (cfg_dir, "gtk-2.0", "settings.ini"),
                Path.build_filename (cfg_dir, "gtk-3.0", "settings.ini"),
                Path.build_filename (cfg_dir, "gtk-4.0", "settings.ini"),
            };
            foreach (string path in paths) {
                write_data (path, looking_for, theme_value);
            }
        }

        private void write_data (string settings_path, string looking_for, string theme_value) {
            File file = File.new_for_path (settings_path);
            // TODO: Implement alt action instead of skipping
            if (!file.query_exists ()) return;

            try {
                string theme_data = "";
                // Read data
                var dis = new DataInputStream (file.read ());
                string ref_lines = "";
                string read_line;
                while ((read_line = dis.read_line (null)) != null) {
                    ref_lines += "%s\n".printf (read_line);
                    var split = read_line.split ("=");
                    if (split.length > 1) {
                        if (split[0] == looking_for) {
                            read_line = "%s=%s".printf (split[0], theme_value);
                        }
                    }
                    theme_data += "%s\n".printf (read_line);
                }
                dis.close ();
                if (ref_lines == theme_data) {
                    debug ("Skipped writing config: %s\n", settings_path);
                    return;
                }

                // Write data
                file.replace_contents (theme_data.data,
                                       null,
                                       false,
                                       GLib.FileCreateFlags.REPLACE_DESTINATION,
                                       null);
            } catch (Error e) {
                print ("Theme Writing Error: %s\n", e.message);
                return;
            }
        }

        string ? get_current_gtk_theme (string type) {
            if (settings.settings_schema.has_key (type)) {
                return settings.get_string (type);
            }
            return null;
        }

        ArrayList<string> get_gtk_themes (string setting_name, string folder_name) {
            string[] paths = Environment.get_system_data_dirs ();

            paths += Environment.get_user_data_dir ();
            for (var i = 0; i < paths.length; i++) {
                paths[i] = Path.build_path ("/", paths[i], folder_name);
            }
            paths += @"$(Environment.get_home_dir ())/.$(folder_name)";

            var themes = new ArrayList<string> ();

            var min_ver = Gtk.get_minor_version ();
            if (min_ver % 2 != 0) min_ver++;

            foreach (string path in paths) {
                while(FileUtils.test(path, FileTest.IS_SYMLINK)) {
                   path = FileUtils.read_link(path);
                }
                if (!FileUtils.test (path, FileTest.IS_DIR)) continue;
                try {
                    var directory = File.new_for_path (path);
                    var enumerator = directory.enumerate_children (
                        FileAttribute.STANDARD_NAME, 0);
                    FileInfo file_prop;
                    while ((file_prop = enumerator.next_file ()) != null) {
                        var child_file_path = Path.build_path("/", path, file_prop.get_name());
                        while(FileUtils.test(child_file_path, FileTest.IS_SYMLINK)) {
                          child_file_path = FileUtils.read_link(child_file_path);
                        }
                        var child_file = File.new_for_path(child_file_path);
                        file_prop = child_file.query_info("*", 0);

                        string name = file_prop.get_name ();
                        string folder_path = Path.build_path ("/", path, name);
                        string flatpak_path = Path.build_path (
                            "/", "flatpak", "exports", "share", folder_name);
                        if (FileType.DIRECTORY != file_prop.get_file_type ()
                            || path.contains (flatpak_path)) {
                            continue;
                        }

                        switch (folder_name) {
                            case "themes":
                                var new_path = @"$(folder_path)/gtk-3.";
                                var file_v3 = File.new_for_path (@"$(new_path)0/gtk.css");
                                var file_min_ver = File.new_for_path (
                                    new_path + min_ver.to_string () + "/gtk.css");
                                if (file_v3.query_exists ()
                                    || file_min_ver.query_exists ()) {
                                    themes.add (name);
                                }
                                break;
                            case "icons":
                                if (get_icons (setting_name, folder_path)) {
                                    themes.add (name);
                                }
                                break;
                        }
                    }
                } catch (Error e) {
                    print ("Error: %s\n", e.message);
                }
            }
            themes.sort ((a, b) => {
                if (a == b) return 0;
                return a > b ? 1 : -1;
            });
            return themes;
        }

        bool get_icons (string setting_name, string folder_path) throws Error {
            switch (setting_name) {
                case "cursor-theme":
                    var cursors_file = File.new_for_path (@"$(folder_path)/cursors");
                    FileType file_type = cursors_file.query_file_type (
                        FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                    if (file_type == FileType.DIRECTORY) return true;
                    break;
                case "icon-theme":
                    var theme_file = File.new_for_path (
                        @"$(folder_path)/index.theme");
                    var file_type = theme_file.query_file_type (0);
                    if (FileType.REGULAR == file_type) {
                        var dir = File.new_for_path (folder_path);
                        var enu = dir.enumerate_children (
                            FileAttribute.STANDARD_NAME,
                            FileQueryInfoFlags.NOFOLLOW_SYMLINKS);
                        FileInfo prop;
                        while ((prop = enu.next_file ()) != null) {
                            if (prop.get_file_type () == FileType.DIRECTORY) {
                                string file_name = prop.get_name ().down ();
                                // validate ex: 384x384 or 16x16
                                bool valid_res = false;
                                string[] name_split = file_name.split ("x");
                                if (name_split.length == 2) {
                                    valid_res =
                                        int.parse (name_split[0]) > 0
                                        && int.parse (name_split[0]) > 0;
                                }

                                if (file_name == "scalable"
                                    || file_name == "symbolic"
                                    || valid_res) {
                                    return true;
                                }
                            }
                        }
                    }
                    break;
            }
            return false;
        }
    }
}
