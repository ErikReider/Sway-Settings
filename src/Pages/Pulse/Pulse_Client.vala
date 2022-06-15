using PulseAudio;
using Gee;

namespace SwaySettings {
    /**
     * Loosely based off of Elementary OS switchboard-plug-sound
     * https://github.com/elementary/switchboard-plug-sound
     */
    public class PulseClient : Object {
        private Context context;
        private GLibMainLoop mainloop;
        private bool quitting = false;


        private string default_sink_name { get; private set; }
        private string default_source_name { get; private set; }

        private PulseDevice ? default_sink = null;
        private PulseDevice ? default_source = null;

        public HashMap<string, PulseDevice> sinks { get; private set; }
        public HashMap<string, PulseDevice> sources { get; private set; }

        public HashMap<uint32, PulseSinkInput> active_sinks { get; private set; }


        construct {
            mainloop = new GLibMainLoop ();

            sinks = new HashMap<string, PulseDevice> ();
            sources = new HashMap<string, PulseDevice> ();

            active_sinks = new HashMap<uint32, PulseSinkInput> ();
        }

        public void start () {
            get_context ();
        }

        public void close () {
            context.disconnect ();
            context = null;
            quitting = false;
        }

        public signal void change_default_device (PulseDevice device);

        public signal void new_active_sink (PulseSinkInput device);
        public signal void change_active_sink (PulseSinkInput device);
        public signal void remove_active_sink (PulseSinkInput device);

        public signal void new_device (PulseDevice device);
        public signal void change_device (PulseDevice device);
        public signal void remove_device (PulseDevice device);

        private void get_context () {
            if (quitting) {
                close ();
            } else {
                quitting = true;
            }
            var ctx = new Context (mainloop.get_api (), null);
            ctx.set_state_callback ((ctx) => {
                switch (ctx.get_state ()) {
                    case Context.State.CONNECTING:
                    case Context.State.AUTHORIZING:
                    case Context.State.SETTING_NAME:
                        break;
                    case Context.State.READY:
                        debug ("Pulse is ready\n");
                        ctx.set_subscribe_callback (subscription);
                        ctx.subscribe (Context.SubscriptionMask.SINK_INPUT |
                                       Context.SubscriptionMask.SINK |
                                       Context.SubscriptionMask.SOURCE_OUTPUT |
                                       Context.SubscriptionMask.SOURCE |
                                       Context.SubscriptionMask.CARD |
                                       Context.SubscriptionMask.SERVER);
                        // Init data
                        ctx.get_server_info (this.get_server_info);
                        break;
                    case Context.State.TERMINATED:
                    case Context.State.FAILED:
                        if (quitting) {
                            quitting = false;
                            break;
                        }
                        stderr.printf (
                            "PulseAudio connection lost. Will retry connection.\n");
                        get_context ();
                        break;
                    default:
                        stderr.printf ("Connection failure: %s\n",
                                       PulseAudio.strerror (ctx.errno ()));
                        break;
                }
            });
            if (ctx.connect (
                    null, Context.Flags.NOFAIL, null) < 0) {
                stdout.printf ("pa_context_connect() failed: %s\n",
                               PulseAudio.strerror (ctx.errno ()));
            }
            this.context = ctx;
        }

        private void subscription (Context ctx,
                                   Context.SubscriptionEventType t,
                                   uint32 index) {
            var type = t & Context.SubscriptionEventType.FACILITY_MASK;
            var event = t & Context.SubscriptionEventType.TYPE_MASK;
            switch (type) {
                case Context.SubscriptionEventType.SINK_INPUT:
                    switch (event) {
                        default: break;
                        case Context.SubscriptionEventType.NEW:
                        case Context.SubscriptionEventType.CHANGE:
                            ctx.get_sink_input_info_list (this.get_sink_input_info);
                            break;
                        case Context.SubscriptionEventType.REMOVE:
                            // A safe way of removing the sink_input
                            var iter = active_sinks.map_iterator ();
                            while (iter.next ()) {
                                var sink_input = iter.get_value ();
                                if (sink_input.index != index) continue;
                                this.remove_active_sink (sink_input);
                                iter.unset ();
                                break;
                            }
                            break;
                    }
                    break;
                case Context.SubscriptionEventType.SINK:
                    switch (event) {
                        default: break;
                        case Context.SubscriptionEventType.NEW:
                        case Context.SubscriptionEventType.CHANGE:
                            ctx.get_sink_info_by_index (index, this.get_sink_info);
                            break;
                        case Context.SubscriptionEventType.REMOVE:
                            foreach (var sink in sinks.values) {
                                if (sink.device_index != index) continue;
                                sink.removed = true;
                                sink.is_default = false;
                                this.remove_device (sink);
                                break;
                            }
                            break;
                    }
                    break;
                case Context.SubscriptionEventType.SOURCE_OUTPUT:
                case Context.SubscriptionEventType.SOURCE:
                    switch (event) {
                        default: break;
                        case Context.SubscriptionEventType.NEW:
                        case Context.SubscriptionEventType.CHANGE:
                            ctx.get_source_info_by_index (index, this.get_source_info);
                            break;
                        case Context.SubscriptionEventType.REMOVE:
                            foreach (var source in sources.values) {
                                if (source.device_index != index) continue;
                                source.removed = true;
                                source.is_default = false;
                                this.remove_device (source);
                                break;
                            }
                            break;
                    }
                    break;
                case Context.SubscriptionEventType.CARD:
                    switch (event) {
                        default: break;
                        case Context.SubscriptionEventType.NEW:
                        case Context.SubscriptionEventType.CHANGE:
                            ctx.get_card_info_by_index (index, this.get_card_info);
                            break;
                        case Context.SubscriptionEventType.REMOVE:
                            // A safe way of removing the sink_input
                            HashMap<string, PulseDevice>[] both = {
                                sources, sinks
                            };
                            foreach (var list in both) {
                                var iter = list.map_iterator ();
                                while (iter.next ()) {
                                    var device = iter.get_value ();
                                    if (device.card_index != index) continue;
                                    device.removed = true;
                                    device.is_default = false;
                                    iter.unset ();
                                    this.remove_device (device);
                                    break;
                                }
                            }
                            break;
                    }
                    break;
                case Context.SubscriptionEventType.SERVER:
                    ctx.get_server_info (this.get_server_info);
                    break;
                default: break;
            }
        }

        /*
         * Getters
         */

        /**
         * Gets called when any server value changes like default devices
         * Calls `get_card_info_list`, `get_sink_info_list` and `get_source_info_list`
         */
        private void get_server_info (Context ctx, ServerInfo ? info) {
            if (this.default_sink_name == null) {
                this.default_sink_name = info.default_sink_name;
            }
            if (this.default_sink_name != info.default_sink_name) {
                this.default_sink_name = info.default_sink_name;
            }

            if (this.default_source_name == null) {
                this.default_source_name = info.default_source_name;
            }
            if (this.default_source_name != info.default_source_name) {
                this.default_source_name = info.default_source_name;
            }

            ctx.get_card_info_list (this.get_card_info);
            ctx.get_sink_info_list (this.get_sink_info);
            ctx.get_source_info_list (this.get_source_info);

            ctx.get_sink_input_info_list (this.get_sink_input_info);
        }

        private void get_sink_input_info (Context ctx, SinkInputInfo ? info, int eol) {
            if (info == null || eol != 0) return;

            uint32 id = PulseSinkInput.get_hash_map_key (info.index);
            PulseSinkInput sink_input = null;
            bool has_sink_input = active_sinks.has_key (id);
            if (has_sink_input) {
                sink_input = active_sinks.get (id);
            } else {
                sink_input = new PulseSinkInput ();
            }

            sink_input.index = info.index;
            sink_input.sink_index = info.sink;
            sink_input.client_index = info.client;

            sink_input.name = info.proplist.gets ("application.name");
            sink_input.application_binary = info.proplist
                                             .gets ("application.process.binary");
            sink_input.application_icon_name = info.proplist
                                                .gets ("application.icon_name");
            sink_input.media_name = info.proplist.gets ("media.name");

            sink_input.is_muted = info.mute == 1;

            sink_input.cvolume = info.volume;
            sink_input.channel_map = info.channel_map;
            sink_input.balance = sink_input.cvolume
                                  .get_balance (sink_input.channel_map);
            sink_input.volume_operations.foreach ((op) => {
                if (op.get_state () != Operation.State.RUNNING) {
                    sink_input.volume_operations.remove (op);
                }
                return Source.CONTINUE;
            });
            if (sink_input.volume_operations.is_empty) {
                sink_input.volume = volume_to_double (
                    sink_input.cvolume.max ());
            }

            if (!has_sink_input) {
                active_sinks.set (id, sink_input);
                this.new_active_sink (sink_input);
            } else {
                this.change_active_sink (sink_input);
            }
        }

        private void get_card_info (Context ctx, CardInfo ? info, int eol) {
            if (info == null || eol != 0) return;

            unowned string ? description = info.proplist
                                            .gets ("device.description");
            unowned string ? props_icon = info.proplist
                                           .gets ("device.icon_name");

            PulseDevice[] ports = {};
            foreach (var port in info.ports) {
                if (port->available == PortAvailable.NO) continue;

                bool is_input = port->direction == Direction.INPUT;
                HashMap<string, PulseDevice> devices =
                    is_input ? this.sources : this.sinks;
                string id = PulseDevice.get_hash_map_key (
                    description, port.name);

                bool has_device = devices.has_key (id);
                PulseDevice device = has_device
                    ? devices.get (id) : new PulseDevice ();
                bool device_is_removed = device.removed;
                device.removed = false;

                device.is_bluetooth = info.proplist.gets ("device.api") == "bluez5";

                device.card_index = info.index;
                device.direction = port.direction;

                device.card_name = info.name;
                device.card_description = description;
                device.card_active_profile = info.active_profile2->name;

                device.port_name = port.name;
                device.port_description = port.description;
                device.port_id = port->proplist.gets ("card.profile.port");

                // Get port profiles2 (profiles is "Superseded by profiles2")
                // and sort largest priority first
                var profiles = new ArrayList<unowned CardProfileInfo2 *>
                                .wrap (port->profiles2);

                profiles.sort ((a, b) => {
                    if (a->priority == b->priority) return 0;
                    return a.priority > b.priority ? -1 : 1;
                });
                string[] new_profiles = {};
                PulseCardProfile[] pulse_profiles = {};
                foreach (var profile in profiles) {
                    new_profiles += profile->name;

                    var card_profile = new PulseCardProfile (profile);
                    pulse_profiles += card_profile;
                    if (profile->name == device.card_active_profile) {
                        device.active_profile = card_profile;
                    }
                }
                device.port_profiles = new_profiles;
                device.profiles = pulse_profiles;

                device.icon_name = port->proplist.gets ("device.icon_name")
                                   ?? props_icon;
                if (device.icon_name == null) {
                    device.icon_name = is_input
                        ? "microphone-sensitivity-high"
                                       : "audio-speakers";
                }
                devices.set (id, device);
                ports += device;
                if (!has_device || device_is_removed) {
                    this.new_device (device);
                }
            }

            /** Removes ports that are no longer available */
            HashMap<string, PulseDevice>[] both = {
                sources, sinks
            };
            foreach (var list in both) {
                var iter = list.map_iterator ();
                while (iter.next ()) {
                    var device = iter.get_value ();
                    if (device.card_index != info.index) continue;
                    bool found = false;
                    foreach (var p in ports) {
                        if (device.get_current_hash_key ()
                            == p.get_current_hash_key ()) {
                            found = true;
                            break;
                        }
                    }
                    if (!found) {
                        iter.unset ();
                        remove_device (device);
                        break;
                    }
                }
            }
        }

        private void get_sink_info (Context ctx, SinkInfo ? info, int eol) {
            if (info == null || eol != 0) return;

            bool found = false;
            foreach (PulseDevice device in sinks.values) {
                if (device.card_index == info.card) {
                    // Sets the name and index to profiles that aren't active
                    // Ex: The HDMI audio port that's not active
                    device.device_name = info.name;
                    device.device_description = info.description;
                    device.device_index = info.index;
                    // If the current selected sink profile is this
                    if (info.active_port != null
                        && info.active_port->name == device.port_name) {
                        found = true;

                        device.card_sink_port_name = info.active_port->name;
                        bool is_default =
                            device.device_name == this.default_sink_name;
                        device.is_default = is_default;

                        device.is_muted = info.mute == 1;

                        device.is_virtual = info.proplist.gets ("node.virtual") == "true";

                        device.cvolume = info.volume;
                        device.channel_map = info.channel_map;
                        device.balance = device.cvolume
                                          .get_balance (device.channel_map);
                        device.volume_operations.foreach ((op) => {
                            if (op.get_state () != Operation.State.RUNNING) {
                                device.volume_operations.remove (op);
                            }
                            return Source.CONTINUE;
                        });
                        if (device.volume_operations.is_empty) {
                            device.volume = volume_to_double (
                                device.cvolume.max ());
                        }

                        if (is_default) {
                            this.default_sink = device;
                            this.change_default_device (device);
                        }
                    }
                    this.change_device (device);
                }
            }
            // If not found, it's a cardless device
            if (found) return;

            HashMap<string, PulseDevice> devices = this.sinks;
            string id = PulseDevice.get_hash_map_key (
                info.index.to_string (), info.description);
            bool has_device = devices.has_key (id);
            PulseDevice device = has_device ? devices.get (id) : new PulseDevice ();

            bool device_is_removed = device.removed;
            device.removed = false;

            device.has_card = false;

            device.direction = PulseAudio.Direction.OUTPUT;

            device.device_name = info.name;
            device.device_description = info.description;
            device.device_index = info.index;

            bool is_default = device.device_name == this.default_source_name;
            device.is_default = is_default;

            device.is_muted = info.mute == 1;

            device.is_virtual = info.proplist.gets ("node.virtual") == "true";

            device.icon_name = "application-x-executable-symbolic";

            device.cvolume = info.volume;
            device.channel_map = info.channel_map;
            device.balance = device.cvolume
                              .get_balance (device.channel_map);
            device.volume_operations.foreach ((op) => {
                if (op.get_state () != Operation.State.RUNNING) {
                    device.volume_operations.remove (op);
                }
                return Source.CONTINUE;
            });
            if (device.volume_operations.is_empty) {
                device.volume = volume_to_double (
                    device.cvolume.max ());
            }

            devices.set (id, device);

            if (is_default) {
                this.default_sink = device;
                this.change_default_device (device);
            }
            if (!has_device || device_is_removed) {
                this.new_device (device);
            }
            this.change_device (device);
        }

        private void get_source_info (Context ctx, SourceInfo ? info, int eol) {
            if (info == null || eol != 0) return;

            // To ignore source monitors (mirroring the sink)
            if (info.monitor_of_sink != PulseAudio.INVALID_INDEX) return;

            bool found = false;
            foreach (PulseDevice device in sources.values) {
                if (device.card_index == info.card) {
                    // Sets the name and index to profiles that aren't active
                    // Ex: The HDMI audio port that's not active
                    device.device_name = info.name;
                    device.device_description = info.description;
                    device.device_index = info.index;
                    // If the current selected source profile is this
                    if (info.active_port != null
                        && info.active_port->name == device.port_name) {
                        found = true;

                        device.card_source_port_name = info.active_port->name;
                        bool is_default =
                            device.device_name == this.default_source_name;
                        device.is_default = is_default;

                        device.is_muted = info.mute == 1;

                        device.is_virtual = info.proplist.gets ("node.virtual") == "true";

                        device.cvolume = info.volume;
                        device.channel_map = info.channel_map;
                        device.balance = device.cvolume
                                          .get_balance (device.channel_map);
                        device.volume_operations.foreach ((op) => {
                            if (op.get_state () != Operation.State.RUNNING) {
                                device.volume_operations.remove (op);
                            }
                            return Source.CONTINUE;
                        });
                        if (device.volume_operations.is_empty) {
                            device.volume = volume_to_double (
                                device.cvolume.max ());
                        }

                        if (is_default) {
                            this.default_source = device;
                            this.change_default_device (device);
                        }
                    }
                    this.change_device (device);
                }
            }
            // If not found, it's a cardless device
            if (found) return;

            HashMap<string, PulseDevice> devices = this.sources;
            string id = PulseDevice.get_hash_map_key (
                info.index.to_string (), info.description);
            bool has_device = devices.has_key (id);
            PulseDevice device = has_device ? devices.get (id) : new PulseDevice ();

            bool device_is_removed = device.removed;
            device.removed = false;

            device.has_card = false;

            device.direction = PulseAudio.Direction.INPUT;

            device.device_name = info.name;
            device.device_description = info.description;
            device.device_index = info.index;

            bool is_default = device.device_name == this.default_source_name;
            device.is_default = is_default;

            device.is_muted = info.mute == 1;

            device.is_virtual = info.proplist.gets ("node.virtual") == "true";

            device.icon_name = "application-x-executable-symbolic";

            device.cvolume = info.volume;
            device.channel_map = info.channel_map;
            device.balance = device.cvolume
                              .get_balance (device.channel_map);
            device.volume_operations.foreach ((op) => {
                if (op.get_state () != Operation.State.RUNNING) {
                    device.volume_operations.remove (op);
                }
                return Source.CONTINUE;
            });
            if (device.volume_operations.is_empty) {
                device.volume = volume_to_double (
                    device.cvolume.max ());
            }

            devices.set (id, device);

            if (is_default) {
                this.default_source = device;
                this.change_default_device (device);
            }
            if (!has_device || device_is_removed) {
                this.new_device (device);
            }
            this.change_device (device);
        }

        /*
         * Setters
         */
        public void set_sink_input_volume (PulseSinkInput sink_input, double volume) {
            sink_input.volume_operations.foreach ((operation) => {
                if (operation.get_state () == Operation.State.RUNNING) {
                    operation.cancel ();
                }

                sink_input.volume_operations.remove (operation);
                return GLib.Source.CONTINUE;
            });

            var cvol = sink_input.cvolume;
            cvol.scale (double_to_volume (volume));
            Operation ? operation = null;
            operation = context.set_sink_input_volume (
                sink_input.index, cvol);
            if (operation != null) {
                sink_input.volume_operations.add (operation);
            }
        }

        public void set_device_volume (PulseDevice device, double volume) {
            device.volume_operations.foreach ((operation) => {
                if (operation.get_state () == Operation.State.RUNNING) {
                    operation.cancel ();
                }

                device.volume_operations.remove (operation);
                return GLib.Source.CONTINUE;
            });

            var cvol = device.cvolume;
            cvol.scale (double_to_volume (volume));
            Operation ? operation = null;
            if (device.direction == Direction.INPUT) {
                operation = context.set_source_volume_by_name (
                    device.device_name, cvol);
            } else {
                operation = context.set_sink_volume_by_name (
                    device.device_name, cvol);
            }

            if (operation != null) {
                device.volume_operations.add (operation);
            }
        }

        public async void set_default_device (PulseDevice device) {
            if (device == null) return;
            bool is_input = device.direction == Direction.INPUT;

            // Only set port and card profile if the device is attached to a card
            if (device.has_card) {
                // Gets the profile that includes support for your other device
                string profile_name = device.port_profiles[0];
                PulseDevice alt_device = is_input ? default_sink : default_source;
                if (alt_device != null) {
                    foreach (var profile in device.port_profiles) {
                        if (profile in alt_device.port_profiles) {
                            profile_name = profile;
                            break;
                        }
                    }
                }

                if (profile_name != device.card_active_profile) {
                    yield set_card_profile_by_index (profile_name, device);
                    yield wait_for_update<string> (device, "device-name");
                }

                if (is_input) {
                    if (device.port_name != device.card_source_port_name) {
                        debug ("Setting port to: %s", device.port_name);
                        yield set_source_port_by_name (device);
                    }
                } else {
                    if (device.port_name != device.card_sink_port_name) {
                        debug ("Setting port to: %s", device.port_name);
                        yield set_sink_port_by_name (device);
                    }
                }

                if (device.device_name == null) {
                    yield wait_for_update<string> (device, "device-name");
                }
            }

            if (is_input) {
                if (device.device_name != default_sink_name) {
                    debug ("Setting default source to: %s", device.device_name);
                    yield set_default_source (device);
                }
            } else {
                if (device.device_name != default_sink_name) {
                    debug ("Setting default sink to: %s", device.device_name);
                    yield set_default_sink (device);
                }
            }
        }

        private async void wait_for_update<T> (PulseDevice device,
                                               string prop_name) {
            SourceFunc callback = wait_for_update.callback;
            ulong handler_id = 0;
            handler_id = device.notify[prop_name].connect ((s, p) => {
                T prop_value;
                device.get (prop_name, out prop_value);
                if (prop_value != null) {
                    device.disconnect (handler_id);
                    Idle.add ((owned) callback);
                }
            });
            yield;
        }

        public async void set_bluetooth_card_profile (PulseCardProfile profile,
                                                      PulseDevice device) {
            context.set_card_profile_by_index (device.card_index,
                                               profile.name,
                                               (c, success) => {
                if (success == 1) {
                    set_bluetooth_card_profile.callback ();
                } else {
                    stderr.printf ("setting the card %s profile to %s failed\n",
                                   device.card_name, profile.name);
                }
            });
            yield;
            // Wait until the device has been updated
            yield wait_for_update<string> (device, "device-name");
        }

        private async void set_card_profile_by_index (string profile_name,
                                                      PulseDevice device) {
            context.set_card_profile_by_index (device.card_index,
                                               profile_name,
                                               (c, success) => {
                if (success == 1) {
                    set_card_profile_by_index.callback ();
                } else {
                    stderr.printf ("setting the card %s profile to %s failed\n",
                                   device.card_name, profile_name);
                }
            });
            yield;
        }

        private async void set_source_port_by_name (PulseDevice device) {
            context.set_source_port_by_name (device.device_name,
                                             device.port_name,
                                             (c, success) => {
                if (success == 1) {
                    set_source_port_by_name.callback ();
                } else {
                    stderr.printf ("setting source port to %s failed\n",
                                   device.port_name);
                }
            });
            yield;
        }

        private async void set_sink_port_by_name (PulseDevice device) {
            context.set_sink_port_by_name (device.device_name,
                                           device.port_name,
                                           (c, success) => {
                if (success == 1) {
                    set_sink_port_by_name.callback ();
                } else {
                    stderr.printf ("setting sink port to %s failed\n",
                                   device.port_name);
                }
            });
            yield;
        }

        private async void set_default_source (PulseDevice device) {
            context.set_default_source (device.device_name, (c, success) => {
                if (success == 1) {
                    set_default_source.callback ();
                } else {
                    stderr.printf ("setting default source to %s failed\n",
                                   device.device_name);
                }
            });
            yield;
        }

        private async void set_default_sink (PulseDevice device) {
            context.set_default_sink (device.device_name, (c, success) => {
                if (success == 1) {
                    set_default_sink.callback ();
                } else {
                    stderr.printf ("setting default sink to %s failed\n",
                                   device.device_name);
                }
            });
            yield;
        }

        public void set_device_mute (bool state, PulseDevice device) {
            if (device.is_muted == state) return;
            switch (device.direction) {
                case Direction.INPUT:
                    context.set_source_mute_by_index (
                        device.device_index, state);
                    break;
                case Direction.OUTPUT:
                    context.set_sink_mute_by_index (
                        device.device_index, state);
                    break;
            }
        }

        public void set_sink_input_mute (bool state, PulseSinkInput sink_input) {
            if (sink_input.is_muted == state) return;
            context.set_sink_input_mute (sink_input.index, state);
        }

        /*
         * Volume utils
         */

        private static double volume_to_double (PulseAudio.Volume vol) {
            double tmp = (double) (vol - PulseAudio.Volume.MUTED);
            return 100 * tmp / (double) (PulseAudio.Volume.NORM - PulseAudio.Volume.MUTED);
        }

        private static PulseAudio.Volume double_to_volume (double vol) {
            double tmp = (double) (PulseAudio.Volume.NORM - PulseAudio.Volume.MUTED) * vol / 100;
            return (PulseAudio.Volume) tmp + PulseAudio.Volume.MUTED;
        }
    }
}
