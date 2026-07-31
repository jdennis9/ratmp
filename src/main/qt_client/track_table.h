#pragma once

#include <QTableWidget>
#include <QWidget>
#include <QVBoxLayout>
#include <QHeaderView>
#include <QLabel>
#include <QList>
#include "defs.h"
#include "../c_interface/c_interface.h"

enum Track_Column {
	TRACK_COLUMN_TITLE,
	TRACK_COLUMN_ALBUM,
	TRACK_COLUMN_ARTIST,
	TRACK_COLUMN_GENRE,
	TRACK_COLUMN_DURATION,
	TRACK_COLUMN__COUNT,
};

/*class Track_Table : public QWidget {
	Q_OBJECT

	QVBoxLayout m_layout;
	
public:
	Track_Table(
		RATMP_Track_ID *tracks, int track_count, QWidget *parent = nullptr
	) : QWidget(parent),  m_layout(this) {

		QTableWidget *table = new QTableWidget(track_count, COLUMN__COUNT);

		m_layout.addWidget(table);
		table->setSelectionBehavior(QAbstractItemView::SelectionBehavior::SelectRows);

		table->verticalHeader()->setDefaultSectionSize(table->verticalHeader()->fontMetrics().height()+1);
		table->verticalHeader()->hide();

		table->setHorizontalHeaderItem(COLUMN_TITLE,    new QTableWidgetItem("Title"));
		table->setHorizontalHeaderItem(COLUMN_ALBUM,    new QTableWidgetItem("Album"));
		table->setHorizontalHeaderItem(COLUMN_ARTIST,   new QTableWidgetItem("Artist"));
		table->setHorizontalHeaderItem(COLUMN_GENRE,    new QTableWidgetItem("Genre"));
		table->setHorizontalHeaderItem(COLUMN_DURATION, new QTableWidgetItem("Duration"));
		//table->horizontalHeader()->setSectionResizeMode(QHeaderView::ResizeMode::Stretch);

		table->setEditTriggers(QAbstractItemView::EditTrigger::NoEditTriggers);

		connect(table, &QTableWidget::itemDoubleClicked, this, &Track_Table::handle_row_double_click);

		for (int i = 0; i < track_count; ++i) {
			RATMP_Track track;

			if (!ratmp_get_track(tracks[i], &track)) continue;

			// Title
			QTableWidgetItem *title = new QTableWidgetItem(to_qstring(track.title));
			title->setData(Qt::UserRole, tracks[i]);
			table->setItem(i, COLUMN_TITLE, title);

			// Album
			if (track.has_album) {
				table->setItem(
					i, COLUMN_ALBUM, 
					new QTableWidgetItem(to_qstring(ratmp_get_shared_string(
						RATMP_SHARED_STRING_ALBUM, track.album
					)))
				);
			}

			// Artists
			if (track.artist_count > 0) {
				QString artists;
				for (int i = 0; i < track.artist_count; ++i) {
					RATMP_String a = ratmp_get_shared_string(RATMP_SHARED_STRING_ARTIST, track.artists[i]);
					artists.append(to_qstring(a));
					if (i != track.artist_count - 1) artists.append(L", ");
				}

				table->setItem(i, COLUMN_ARTIST, new QTableWidgetItem(artists));
			}

			// Genres
			if (track.genre_count > 0) {
				QString genres;
				for (int i = 0; i < track.genre_count; ++i) {
					RATMP_String a = ratmp_get_shared_string(RATMP_SHARED_STRING_GENRE, track.genres[i]);
					genres.append(to_qstring(a));
					if (i != track.genre_count - 1) genres.append(L", ");
				}

				table->setItem(i, COLUMN_GENRE, new QTableWidgetItem(genres));
			}

			// Duration
			int h, m, s;
			seconds_to_hms(track.duration, h, m, s);
			
			table->setItem(
				i, COLUMN_DURATION, new QTableWidgetItem(QString::asprintf("%02d:%02d:%02d", h, m, s))
			);
		}

		table->setSortingEnabled(true);
	}

	~Track_Table() {}

	void handle_row_double_click(QTableWidgetItem *item) {
		RATMP_Track_ID id = item->data(Qt::UserRole).toUInt();
		RATMP_Track track{};

		if (ratmp_get_track(id, &track)) {
			ratmp_play_file(track.url);
		}
	}
};*/

class Track_Model : public QAbstractTableModel {
	Q_OBJECT
	QList<RATMP_Track_ID> m_tracks;

public:
	Track_Model(RATMP_Track_ID *tracks, int track_count, QObject *parent = nullptr) 
	: QAbstractTableModel(parent), m_tracks(tracks, &tracks[track_count]) {

	}

	const QList<RATMP_Track_ID>& tracks() const {
		return m_tracks;
	}

	int rowCount(const QModelIndex& parent = QModelIndex()) const override {
		return m_tracks.length();
	}

	int columnCount(const QModelIndex& parent = QModelIndex()) const override {
		return TRACK_COLUMN__COUNT;
	}

	QVariant data(const QModelIndex &index, int role = Qt::DisplayRole) const override {
		RATMP_Track track{};

		if (role != Qt::DisplayRole) return QVariant();

		RATMP_Track_ID id = m_tracks[index.row()];

		if (!ratmp_get_track(id, &track)) return QVariant();

		switch (index.column()) {
		case TRACK_COLUMN_TITLE: return to_qstring(track.title);
		case TRACK_COLUMN_ALBUM:
			if (!track.has_album) return QVariant();
			return to_qstring(ratmp_get_shared_string(RATMP_SHARED_STRING_ALBUM, track.album));
		case TRACK_COLUMN_ARTIST: {
			QString artists;
			if (track.artist_count <= 0) return QVariant();

			for (int i = 0; i < track.artist_count; ++i) {
				RATMP_String a = ratmp_get_shared_string(RATMP_SHARED_STRING_ARTIST, track.artists[i]);
				artists.append(to_qstring(a));
				if (i != track.artist_count - 1) artists.append(L", ");
			}

			return artists;
		}
		case TRACK_COLUMN_GENRE: {
			QString genres;
			if (track.genre_count <= 0) return QVariant();

			for (int i = 0; i < track.genre_count; ++i) {
				RATMP_String a = ratmp_get_shared_string(RATMP_SHARED_STRING_GENRE, track.genres[i]);
				genres.append(to_qstring(a));
				if (i != track.genre_count - 1) genres.append(L", ");
			}

			return genres;
		}
		case TRACK_COLUMN_DURATION: {
			int h, m, s;
			seconds_to_hms(track.duration, h, m, s);
			return QString::asprintf("%02d:%02d:%02d", h, m, s);
		}
		}

		return QVariant();
	}

	QVariant headerData(int section, Qt::Orientation orientation, int role = Qt::DisplayRole) const override {
		if (role != Qt::DisplayRole || orientation != Qt::Horizontal) return QVariant();
		
		switch (section) {
		case TRACK_COLUMN_ALBUM:    return "Album";
		case TRACK_COLUMN_GENRE:    return "Genre(s)";
		case TRACK_COLUMN_ARTIST:   return "Artist(s)";
		case TRACK_COLUMN_TITLE:    return "Title";
		case TRACK_COLUMN_DURATION: return "Duration";
		}

		return QVariant();
	}
};

class Track_Table : public QWidget {
	Q_OBJECT

	QVBoxLayout m_layout;
	Track_Model m_model;

public:
	Track_Table(
		RATMP_Track_ID *tracks, int track_count, QWidget *parent = nullptr
	) : QWidget(parent), m_model(tracks, track_count), m_layout(this) {

		QTableView *table = new QTableView();

		table->setSelectionBehavior(QAbstractItemView::SelectionBehavior::SelectRows);

		table->setModel(&m_model);
		table->verticalHeader()->setDefaultSectionSize(table->verticalHeader()->fontMetrics().height()+1);
		table->verticalHeader()->hide();

		table->horizontalHeader()->setStretchLastSection(true);

		table->setWordWrap(false);

		this->connect(table, SIGNAL(doubleClicked(const QModelIndex&)), this, SLOT(handle_row_double_clicked(const QModelIndex&)));

		m_layout.addWidget(table);
	}

	~Track_Table() {}

public slots:
	void handle_row_double_clicked(const QModelIndex& index) {
		RATMP_Track_ID track_id = index.data().toUInt();
		const QList<RATMP_Track_ID> tracks = m_model.tracks();
		ratmp_play_playlist(tracks.data(), tracks.length(), 0);
	}
};
