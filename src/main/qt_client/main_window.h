#pragma once

#include "../c_interface/c_interface.h"
#include "track_table.h"
#include "spectrum_window.h"
#include <QMainWindow>
#include <QTimer>
#include <QMenuBar>
#include <DockWidget.h>
#include <DockManager.h>

class Main_Window : public QMainWindow {
	Q_OBJECT

	ads::CDockManager *m_dock_manager;

public:
	Main_Window(QWidget *parent = nullptr) : QMainWindow(parent) {
		m_dock_manager = new ads::CDockManager(this);

		QMenuBar *menu_bar = this->menuBar();
		QMenu *file_menu = menu_bar->addMenu("File");
		file_menu->addAction("Add folders");
		file_menu->addSeparator();
		file_menu->addAction("Exit");

		menu_bar->addSeparator();

		this->connect(menu_bar->addAction("Prev"),   SIGNAL(triggered()), this, SLOT(go_to_previous()));
		this->connect(menu_bar->addAction("Toggle"), SIGNAL(triggered()), this, SLOT(toggle_pause()));
		this->connect(menu_bar->addAction("Next"),   SIGNAL(triggered()), this, SLOT(go_to_next()));

		menu_bar->addSeparator();

		// Library
		{
			RATMP_Track_ID *all_tracks;
			int track_count;

			ads::CDockWidget *dock = m_dock_manager->createDockWidget("Library");

			track_count = ratmp_get_all_track_ids(&all_tracks);

			Track_Table *table = new Track_Table(all_tracks, track_count);
			dock->setWidget(table);

			ratmp_free(all_tracks);
			m_dock_manager->addDockWidget(ads::TopDockWidgetArea, dock);
		}

		// Spectrum
		{
			ads::CDockWidget *dock = m_dock_manager->createDockWidget("Spectrum");
			dock->setWidget(new Spectrum());
			m_dock_manager->addDockWidget(ads::TopDockWidgetArea, dock);
		}
	}

	~Main_Window() {
		delete m_dock_manager;
	}

public slots:
	void go_to_previous(bool checked = false) {
		ratmp_prev();
	}

	void toggle_pause(bool checked = false) {
	}

	void go_to_next(bool checked = false) {
		ratmp_next();
	}
};
