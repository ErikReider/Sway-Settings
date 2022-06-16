using Gee;

namespace SwaySettings {
    private errordomain ThumbnailerError { FAILED; }

    public class Functions {

        public delegate void Delegate_walk_func (FileInfo file_info, File file);

        public static int walk_through_dir (string path, Delegate_walk_func func) {
            try {
                var directory = File.new_for_path (path);
                if (!directory.query_exists ()) return 1;
                var enumerator = directory.enumerate_children (FileAttribute.STANDARD_NAME, 0);
                FileInfo file_prop;
                while ((file_prop = enumerator.next_file ()) != null) {
                    func (file_prop, directory);
                }
            } catch (Error e) {
                print ("Error: %s\n", e.message);
                return 1;
            }
            return 0;
        }

        public static File check_settings_folder_exists (string file_name) {
            string base_path = GLib.Environment.get_user_config_dir () + "/sway/.generated_settings";
            // Checks if directory exists. Creates one if none
            if (!GLib.FileUtils.test (base_path, GLib.FileTest.IS_DIR)) {
                try {
                    var file = File.new_for_path (base_path);
                    file.make_directory ();
                } catch (Error e) {
                    print ("Error: %s\n", e.message);
                }
            }
            // Checks if file exists. Creates one if none
            var file = File.new_for_path (base_path + @"/$(file_name)");
            if (!file.query_exists ()) {
                try {
                    file.create (FileCreateFlags.NONE);
                } catch (Error e) {
                    print ("Error: %s\n", e.message);
                    Process.exit (1);
                }
            }
            return file;
        }

        public static void write_settings (string file_name, string[] lines) {
            try {
                var file = check_settings_folder_exists (file_name);
                var fos = file.replace (null,
                                        false,
                                        FileCreateFlags.REPLACE_DESTINATION,
                                        null);
                var dos = new DataOutputStream (fos);
                dos.put_string (
                    "# GENERATED BY SWAYSETTINGS. DON'T MODIFY THIS FILE!\n");
                foreach (string line in lines) {
                    dos.put_string (line);
                }
            } catch (Error e) {
                print ("Error: %s\n", e.message);
                Process.exit (1);
            }
        }

        public static bool is_swaync_installed () {
            return GLib.Environment.find_program_in_path ("swaync") != null;
        }

        public static string get_swaync_config_path () {
            string[] paths = {};
            paths += Path.build_path (Path.DIR_SEPARATOR.to_string (),
                                      GLib.Environment.get_user_config_dir (),
                                      "swaync/config.json");
            foreach (var path in GLib.Environment.get_system_config_dirs ()) {
                paths += Path.build_path (Path.DIR_SEPARATOR.to_string (),
                                          path, "swaync/config.json");
            }

            string path = "";
            foreach (string try_path in paths) {
                if (File.new_for_path (try_path).query_exists ()) {
                    path = try_path;
                    break;
                }
            }
            return path;
        }

        private delegate Type TypeFunc ();

        /** https://gitlab.gnome.org/GNOME/vala/-/issues/412 */
        public static Type get_proxy_gtype<T> () {
            Quark proxy_quark = Quark.from_string ("vala-dbus-proxy-type");
            return ((TypeFunc) (typeof (T).get_qdata (proxy_quark)))();
        }

        public static string ? set_gsetting (Settings settings,
                                             string name,
                                             Variant value) {
            if (!settings.settings_schema.has_key (name)) return null;

            var v_type = settings.settings_schema.get_key (name).get_value_type ();
            if (!v_type.equal (value.get_type ())) {
                stderr.printf ("Set GSettings error: Set value type not equal to gsettings type\n");
                return null;
            }

            switch (value.get_type_string ()) {
                case "b":
                    bool val = value.get_boolean ();
                    settings.set_boolean (name, val);
                    return val.to_string ();
                case "s":
                    string val = value.get_string ();
                    settings.set_string (name, val);
                    return val;
            }
            return null;
        }

        public static Variant ? get_gsetting (Settings settings,
                                              string name,
                                              VariantType type) {
            if (!settings.settings_schema.has_key (name)) return null;
            var v_type = settings.settings_schema.get_key (name).get_value_type ();
            if (!v_type.equal (type)) {
                stderr.printf ("Set GSettings error: Set value type not equal to gsettings type\n");
                return null;
            }
            return settings.get_value (name);
        }

        public static string ? generate_thumbnail (string p,
                                                   bool delete_past = false) throws Error {
            File file = File.new_for_path (p);
            string path = file.get_uri ();
            string checksum = Checksum.compute_for_string (ChecksumType.MD5, path, path.length);
            string checksum_path = "%s/thumbnails/large/%s.png".printf (
                Environment.get_user_cache_dir (), checksum);

            File sum_file = File.new_for_path (checksum_path);
            bool exists = sum_file.query_exists ();
            // Remove the old file
            if (delete_past && exists) {
                sum_file.delete ();
                exists = false;
            }
            if (!exists) {
                string output;
                string error;
                bool status = Process.spawn_command_line_sync (
                    @"gdk-pixbuf-thumbnailer \"$(p)\" \"$(checksum_path)\"",
                    out output, out error);
                if (!status || error.length > 0) {
                    throw new ThumbnailerError.FAILED (error);
                }
            }

            return checksum_path;
        }
    }
}
