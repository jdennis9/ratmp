package prefs;

import "core:log";
import "core:encoding/json";
import "core:path/filepath";
import "core:os";
import "core:fmt";
import "core:hash/xxhash";

import "player:system_paths";
import "player:util";

Property :: union {
	int,
	bool,
};

Property_Name :: [32]u8;

@private
_properties: struct {
	key_names: [dynamic]Property_Name,
	keys: [dynamic]u32,
	values: [dynamic]Property,
};

get_property_index :: proc(hash: u32) -> (int, bool) {
	for key, index in _properties.keys {
		if hash == key {
			return index, true;
		}
	}
	
	return 0, false;
}

get_property :: proc(name: string) -> Property {
	hash := xxhash.XXH32(transmute([]u8) name);
	index, found := get_property_index(hash);

	if found {
		return _properties.values[index];
	}
	return nil;
}

set_property :: proc(name: string, value: Property) {
	hash := xxhash.XXH32(transmute([]u8) name);
	index, found := get_property_index(hash);

	if found {
		_properties.values[index] = value;
	}
	else {
		name_buf: Property_Name;
		util.copy_string_to_buf(name_buf[:], name);

		append(&_properties.key_names, name_buf);
		append(&_properties.keys, hash);
		append(&_properties.values, value);
	}
}

@private
_save_properties :: proc() -> bool {
	path := filepath.join({system_paths.CONFIG_DIR, "state.json"});
	defer delete(path);

	file, open_error := util.overwrite_file(path);
	if open_error != nil {
		log.error(open_error);
		return false;
	}
	defer os.close(file);

	fmt.fprintln(file, "{");
	defer fmt.fprintln(file, "}");
	fmt.fprintln(file, "\"properties\": {");
	defer fmt.fprintln(file, "}");

	for index in 0..<len(_properties.keys) {
		key := string(cstring(&_properties.key_names[index][0]));
		value := _properties.values[index];
		switch v in value {
			case int: {
				util.json_write_kv_pair(file, key, v, true);
			}
			case bool: {
				util.json_write_kv_pair(file, key, v, true);
			}
		}
	}

	return true;
}

@private
_load_properties :: proc() -> bool {
	path := filepath.join({system_paths.CONFIG_DIR, "state.json"});
	defer delete(path);

	data := os.read_entire_file_from_filename(path) or_return;
	defer delete(data);

	root, parse_error := json.parse(data, .JSON5, true);
	if parse_error != nil {
		log.error(parse_error);
		return false;
	}
	defer json.destroy_value(root);

	root_obj := (root.(json.Object) or_return);
	props_value := root_obj["properties"] or_return;
	props := props_value.(json.Object) or_return;
	kv_loop: for key, value in props {
		#partial switch v in value {
			case json.Integer: {
				set_property(key, int(v));
				continue kv_loop;
			}
			case json.Boolean: {
				set_property(key, v);
				continue kv_loop;
			}
		}

		log.warn("Unimplemented JSON variable type for", key);
	}

	return true;
}
