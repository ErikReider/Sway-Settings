namespace SwaySettings {
    [GtkTemplate (ui = "/org/erikreider/swaysettings/ui/BluetoothDeviceRow.ui")]
    class BluetoothDeviceRow : Gtk.ListBoxRow {
        public enum State {
            UNPAIRED,
            PAIRING,
            CONNECTED,
            CONNECTING,
            DISCONNECTING,
            NOT_CONNECTED,
            ERROR,
            ERROR_PAIRED;

            public string get_status () {
                switch (this) {
                    default:
                    case NOT_CONNECTED:
                    case UNPAIRED:
                        return "";
                    case PAIRING:
                        return "Pairing…";
                    case CONNECTED:
                        return "Connected";
                    case CONNECTING:
                        return "Connecting…";
                    case DISCONNECTING:
                        return "Disconnecting…";
                    case ERROR:
                    case ERROR_PAIRED:
                        return "Unable to Connect";
                }
            }
        }

        [GtkChild]
        private unowned Gtk.Image device_image;
        [GtkChild]
        private unowned Gtk.Label device_name;

        [GtkChild]
        private unowned Gtk.Label status_label;

        [GtkChild]
        private unowned Gtk.Spinner status_spinner;

        [GtkChild]
        private unowned Gtk.Button remove_button;
        [GtkChild]
        private unowned Gtk.Button connect_button;

        public Bluez.Device1 device { get; private set; }
        public Bluez.Adapter1 adapter { get; private set; }

        private ulong props_changed_id;

        /** Gets called when Device Paired, Trusted or Blocked changes */
        public signal void on_update (BluetoothDeviceRow row);

        public BluetoothDeviceRow (Bluez.Device1 device, Bluez.Adapter1 adapter) {
            this.device = device;
            this.adapter = adapter;

            this.connect_button.clicked.connect (() => {
                this.action_button_clicked_cb.begin (() => {
                    device.trusted = device.paired;
                });
            });

            this.remove_button.clicked.connect (this.remove_button_clicked_cb);

            // Watch property changes
            props_changed_id = ((DBusProxy) device).g_properties_changed.connect ((cgd, inv) => {
                // Disconnect if in destruction
                if (is_dead ()) {
                    before_destroy ();
                    return;
                }

                // Updates the ListBox sorting order
                this.changed ();

                var paired = cgd.lookup_value ("Paired", VariantType.BOOLEAN);
                if (paired != null) {
                    device.trusted = device.paired;
                    // Connect to device if just paired
                    device.connect.begin ();
                    on_update (this);
                    update_state ();
                }

                var trusted = cgd.lookup_value ("Trusted", VariantType.BOOLEAN);
                if (trusted != null) {
                    on_update (this);
                    update_state ();
                }

                // Update the state only when paired or connected changes
                var connected = cgd.lookup_value ("Connected", new VariantType ("b"));
                if (connected != null) {
                    on_update (this);
                    update_state ();
                }

                update_widget ();
            });

            update_state ();
            update_widget ();
        }

        private bool is_dead () {
            return !(this.get_child () is Gtk.Widget) || this.in_destruction ();
        }

        public void before_destroy () {
            if (props_changed_id != 0) {
                ((DBusProxy) device).disconnect (props_changed_id);
                props_changed_id = 0;
            }
        }

        private async void action_button_clicked_cb () {
            if (!device.paired) {
                set_row_state (State.PAIRING);
                try {
                    yield device.pair ();
                } catch (Error e) {
                    set_row_state (State.ERROR);
                    stderr.printf ("Device Pairing Error: %s\n", e.message);
                }
            } else if (!device.connected) {
                set_row_state (State.CONNECTING);
                try {
                    yield device.connect ();
                } catch (Error e) {
                    set_row_state (State.ERROR_PAIRED);
                    stderr.printf ("Device Connecting Error: %s\n", e.message);
                }
            } else {
                set_row_state (State.DISCONNECTING);
                try {
                    yield device.disconnect ();
                } catch (Error e) {
                    stderr.printf ("Device Disconnecting Error: %s\n", e.message);
                }
            }
        }

        private void remove_button_clicked_cb () {
            if (!device.paired) return;

            string title = "Remove \"%s\"?".printf (device.alias);
            const string BODY = "If you remove the device, you will have to repair the device to use it.";
            var window = (Adw.ApplicationWindow) this.get_root ();

            var dialog = new Adw.MessageDialog (window, title, BODY);
            dialog.add_responses ("cancel", "Cancel", "remove", "Remove", null);
            dialog.set_response_appearance ("remove", Adw.ResponseAppearance.DESTRUCTIVE);
            dialog.set_default_response ("cancel");
            dialog.set_close_response ("cancel");
            dialog.response.connect ((dialog, response) => {
                if (response == "remove") {
                    try {
                        adapter.remove_device (new ObjectPath (((DBusProxy) device).g_object_path));
                        device.trusted = false;
                    } catch (Error e) {
                        stderr.printf ("Remove device Error: %s\n", e.message);
                    }
                }
            });
            dialog.present ();
        }

        /**
         * Sets all relevant widgets sensitivity to value.
         * Makes sure that remove_button sensitivity is always true
         */
        public void set_row_sensitivity (bool value) {
            this.remove_button.set_sensitive (true);
            this.device_image.set_sensitive (value);
            this.status_label.set_sensitive (value);
            this.device_name.set_sensitive (value);
            this.connect_button.set_sensitive (value);
        }

        public void update_widget () {
            if (is_dead ()) return;

            // Only show devices with low RSSI if paired
            if (!device.paired && !device.connected && device.rssi == 0) {
                set_row_sensitivity (false);
                set_visible (false);
            } else {
                set_row_sensitivity (true);
                set_visible (true);
            }

            device_name.set_label (device.alias);

            const string DEFAULT_ICON = "bluetooth-symbolic";
            string icon = DEFAULT_ICON;
            if (device.icon != null && device.icon.length > 0) icon = device.icon;
            if (!Gtk.IconTheme.get_for_display (get_display ()).has_icon (icon)) {
                icon = DEFAULT_ICON;
            }
            device_image.set_from_icon_name (icon);
            device_image.pixel_size = 48;
        }

        private void update_state () {
            if (is_dead ()) return;

            if (!device.paired) {
                this.set_row_state (State.UNPAIRED);
            } else if (device.connected) {
                this.set_row_state (State.CONNECTED);
            } else {
                this.set_row_state (State.NOT_CONNECTED);
            }
        }

        private void set_row_state (State state) {
            status_label.label = state.get_status ();

            switch (state) {
                case State.ERROR:
                case State.UNPAIRED:
                    // If not paired and not connected
                    connect_button.label = "Pair";
                    connect_button.sensitive = true;
                    status_spinner.stop ();
                    remove_button.visible = false;
                    remove_button.sensitive = false;
                    break;
                case State.PAIRING:
                    // connect_button.label = "Pair";
                    connect_button.sensitive = false;
                    status_spinner.start ();
                    remove_button.visible = false;
                    remove_button.sensitive = false;
                    break;
                case State.CONNECTED:
                    // If paired and connected
                    connect_button.label = "Disconnect";
                    connect_button.sensitive = true;
                    status_spinner.stop ();
                    remove_button.visible = true;
                    remove_button.sensitive = true;
                    break;
                case State.CONNECTING:
                    // connect_button.label = "Disconnect";
                    connect_button.sensitive = false;
                    status_spinner.start ();
                    remove_button.visible = false;
                    remove_button.sensitive = false;
                    break;
                case State.DISCONNECTING:
                    // connect_button.label = "Disconnect";
                    connect_button.sensitive = false;
                    status_spinner.stop ();
                    remove_button.visible = false;
                    remove_button.sensitive = false;
                    break;
                case State.ERROR_PAIRED:
                case State.NOT_CONNECTED:
                    // If paired and not connected
                    connect_button.label = "Connect";
                    connect_button.sensitive = true;
                    status_spinner.stop ();
                    remove_button.visible = true;
                    remove_button.sensitive = true;
                    break;
            }
        }
    }
}
