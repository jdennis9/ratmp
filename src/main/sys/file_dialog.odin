/*
	RAT MP - A cross-platform, extensible music player
	Copyright (C) 2025-2026 Jamie Dennis

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
package sys

FILE_DIALOG_MAX_FILE_TYPES :: 16

File_Dialog_File_Type :: struct {
	name:       string,
	extensions: []string, // include preceeding dot
}

File_Dialog_Params :: struct {
	title:           string,
	file_types:      []File_Dialog_File_Type,
	select_folders:  bool,
	select_multiple: bool,
}
