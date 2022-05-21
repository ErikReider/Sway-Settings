using Gee;

namespace SwaySettings {
    public class Themes_Page : Page_Scroll {
        Settings settings = new Settings ("org.gnome.desktop.interface");

        const string[] color_schemes = { "default", "prefer-dark", "prefer-light" };

        public Themes_Page (string page_name, Hdy.Deck deck) {
            base (page_name, deck);
            // Refresh all of the widgets when a value changes
            // This also gets called when ex gnome-tweaks changes a value
            settings.changed.connect ((settings, str) => this.on_refresh ());
        }

        public override Gtk.Widget set_child () {
            Hdy.PreferencesGroup pref_group = new Hdy.PreferencesGroup ();
            pref_group.set_title ("GTK Settings");

            pref_group.add (
                gtk_theme ("Application Theme", "gtk-theme", "themes"));
            pref_group.add (
                gtk_theme ("Icon Theme", "icon-theme", "icons"));
            pref_group.add (
                gtk_theme ("Cursor Theme", "cursor-theme", "icons"));

            pref_group.add (gtk4_color_scheme ());

            return pref_group;
        }

        private Hdy.ComboRow gtk4_color_scheme () {
            string setting_name = "color-scheme";
            var combo_row = new Hdy.ComboRow ();
            combo_row.set_title ("Gtk4 Color Scheme");

            if (!settings.settings_schema.has_key (setting_name)) {
                combo_row.set_sensitive (false);
                return combo_row;
            }

            ListStore liststore = new ListStore (typeof (Hdy.ValueObject));
            string current_theme = settings.get_string (setting_name);

            if (current_theme == null) {
                combo_row.set_sensitive (false);
                return combo_row;
            }
            int selected_index = 0;
            for (int i = 0; i < color_schemes.length; i++) {
                var theme_name = color_schemes[i];
                liststore.append (new Hdy.ValueObject (theme_name));
                if (current_theme == theme_name) selected_index = i;
            }

            combo_row.bind_name_model ((ListModel) liststore, (item) => {
                return ((Hdy.ValueObject) item).get_string ();
            });
            combo_row.set_selected_index (selected_index);
            combo_row.notify["selected-index"].connect (
                (sender, property) => {
                int i = ((Hdy.ComboRow) sender).get_selected_index ();
                if (i < 0 || i >= color_schemes.length) return;
                string theme = color_schemes[i];
                set_gtk_theme (setting_name, theme);
            });

            return combo_row;
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
                settings.set_string (setting_name, theme);
            });
            return combo_row;
        }

        void set_gtk_theme (string type, string theme_name) {
            if (!settings.settings_schema.has_key (type)) return;

            settings.set_string (type, theme_name);
            // Also set the .config/gtk-3.0/settings.ini
            // (Firefox ignores the gsettings variable)
            string settings_path = Path.build_filename (
                Environment.get_user_config_dir (), "gtk-3.0", "settings.ini");
            var file = File.new_for_path (settings_path);
            // TODO: Implement alt action instead of skipping
            if (!file.query_exists ()) return;
            try {
                string theme_data = "";

                // Read data
                var dis = new DataInputStream (file.read ());
                string read_line;
                while ((read_line = dis.read_line (null)) != null) {
                    var split = read_line.split ("=");
                    if (split.length > 1) {
                        string ? looking_for = "";
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
                        }
                        if (split[0] == looking_for) {
                            read_line = @"$(split[0])=$(theme_name)";
                        }
                    }
                    theme_data += @"$(read_line)\n";
                }
                dis.close ();

                // Write data
                file.replace_contents (theme_data.data,
                                       null,
                                       false,
                                       GLib.FileCreateFlags.REPLACE_DESTINATION,
                                       null);
            } catch (Error e) {
                print ("Error: %s\n", e.message);
                Process.exit (1);
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

            var themes = new ArrayList<string>();

            var min_ver = Gtk.get_minor_version ();
            if (min_ver % 2 != 0) min_ver++;

            foreach (string path in paths) {
                if (!FileUtils.test (path, FileTest.IS_DIR)) continue;
                try {
                    var directory = File.new_for_path (path);
                    var enumerator = directory.enumerate_children (
                        FileAttribute.STANDARD_NAME, 0);
                    FileInfo file_prop;
                    while ((file_prop = enumerator.next_file ()) != null) {
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
