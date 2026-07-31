#include <QApplication>
#include "../c_interface/c_interface.h"
#include "main_window.h"

int main(int argc, char *argv[]) {
	
	if (!ratmp_init()) return 1;

	ratmp_play_file(from_cstring("D:\\Music\\Electronic\\InsideInfo\\Ancestral\\Ancestral [TjqBxpGXv6c].opus"));

	QApplication app(argc, argv);
	app.setStyle("Windows11");
	
	Main_Window main_window;

	main_window.show();
	app.exec();

	ratmp_shutdown();
}
