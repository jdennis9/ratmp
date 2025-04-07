/*
	RAT MP: A lightweight graphical music player
    Copyright (C) 2025 Jamie Dennis

    This program is free software: you can redistribute it and/or modify
    it under the terms of the GNU General Public License as published by
    the Free Software Foundation, either version 3 of the License, or
    (at your option) any later version.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
    GNU General Public License for more details.

    You should have received a copy of the GNU General Public License
    along with this program.  If not, see <https://www.gnu.org/licenses/>.
*/
package ipc;

import "core:net";
import "core:log";
import "core:sys/posix";
import "core:thread";
import "core:time";
import "core:path/filepath";
import "core:os";
import "core:fmt";
import "core:encoding/ini";
import "core:strings";
import "core:strconv";

import "../util";
import "../signal";
import "../system_paths";
import lib "../library";
import "../playback";

@private
ADDRESS := net.Endpoint{
	address = net.IP4_Loopback,
	port = 21374,
};

@private
this: struct {
	listener_thread: ^thread.Thread,
};

@private
listener_proc :: proc(_: ^thread.Thread) {
	ok: bool;
	socket, socket_error := net.create_socket(.IP4, .TCP);
	if socket_error != nil {return}
	defer net.close(socket);

	tcp, tcp_error := net.listen_tcp(ADDRESS);
	if tcp_error != nil {
		log.debug("listen_tcp():", tcp);
		return;
	}

	log.info("Listening for messages on:", ADDRESS);
	
	listen_loop: for {
		client, source, accept_error := net.accept_tcp(tcp);
		if accept_error != nil {continue}

		buf: [1024]u8;
		bytes_read, recv_error := net.recv_tcp(client, buf[:]);
		message := string(buf[:bytes_read]);

		if message == "pause" {signal.post(.RequestPause)}
		else if message == "play" {signal.post(.RequestPlay)}
		else if message == "next" {signal.post(.RequestPrev)}
		else if message == "prev" {signal.post(.RequestNext)}
		else if message == "toggle" {
			if playback.is_paused() {signal.post(.RequestPlay)}
			if playback.is_paused() {signal.post(.RequestPause)}
		}
		else if message == "status" {
			send_buf: [1024]u8;
			track_id := playback.get_playing_track();
			if track_id == 0 {
				bytes_written, send_error := net.send_tcp(client, {'N', '/', 'A'});
				log.debug("Message sent");
				continue listen_loop;
			}
			track := lib.get_track_info(track_id);

			ch, cm, cs := util.split_seconds(i32(playback.get_second()));
			th, tm, ts := util.split_seconds(i32(playback.get_duration()));

			message_to_send := fmt.bprintf(send_buf[:],
				"%s - %s (%02d:%02d:%02d/%02d:%02d:%02d)",
				track.artist, track.title,
				ch, cm, cs,
				th, tm, ts,
			);

			net.send_tcp(client, transmute([]u8) message_to_send);
		}
	}
}

start_listening :: proc() {
	this.listener_thread = thread.create(listener_proc);
	this.listener_thread.init_context = context;
	thread.start(this.listener_thread);
}

send_message :: proc(msg: string) -> (response: string, responded: bool) {
	socket, socket_error := net.dial_tcp_from_endpoint(ADDRESS);
	if socket_error != nil {
		fmt.println("Failed to connect to IPC socket");
		return;
	}

	bytes_written, send_error := net.send_tcp(socket, transmute([]u8) msg);
	if send_error != nil {
		return;
	}

	// If the message expects a response, wait for one
	if msg == "status" {
		buf: [1024]u8;

		bytes_read, recv_error := net.recv_tcp(socket, buf[:]);
		if recv_error != nil {
			return;
		}

		response = strings.clone(string(buf[:bytes_read]));
		responded = true;
		return;
	}

	return;
}

