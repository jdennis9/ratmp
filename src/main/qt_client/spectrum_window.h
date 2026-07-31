#pragma once

#include <QWidget>
#include <QTimer>
#include <QPainter>
#include <stdio.h>
#include "../c_interface/c_interface.h"

class Spectrum : public QWidget {
	Q_OBJECT

	QList<float>     m_bands;
	QList<float>     m_band_frequencies;
	int              m_samplerate;
	int              m_channels;
	RATMP_FFT_State *m_fft;

	void set_band_count(int band_count) {
		float fm = powf(22000.f / 20.f, 1.f / (float)(band_count-1));

		m_band_frequencies.resize(band_count);
		for (int band = 0; band < band_count; ++band) {
			m_band_frequencies[band] = 20.f * powf(fm, (float)band);
		}

		m_bands.resize(band_count);
	}

public:
	Spectrum(QWidget *parent = nullptr) : QWidget(parent) {
		QTimer *timer = new QTimer(this);
		this->connect(timer, SIGNAL(timeout()), this, SLOT(update_bars()));
		timer->start(1000/60);

		this->setBackgroundRole(QPalette::Base);
		this->setAutoFillBackground(true);

		m_fft = ratmp_new_fft();

		this->set_band_count(40);
	}

	~Spectrum() {
		ratmp_destroy_fft(m_fft);
	}

	QSize minimumSizeHint() const override {
		return QSize(20, 20);
	}

	QSize sizeHint() const override {
		return QSize(400, 200);
	}

public slots:
	void update_bars() {
		constexpr int BUFFER_SIZE = 4<<10;
		
		static float buffer_storage[BUFFER_SIZE][2];
		float *buffer[2];


		for (int i = 0; i < 2; ++i) buffer[i] = buffer_storage[i];

		ratmp_consume_output(buffer, 2, BUFFER_SIZE, 1.f/60.f, &m_samplerate, &m_channels);
		
		float *fft;
		int fft_size;

		for (int i = 0; i < BUFFER_SIZE; ++i) {
			buffer[0][i] *= 0.5f * (1.f - cosf((2.f * M_PI * i) / (float)(m_bands.length() - 1)));
		}

		ratmp_fft(m_fft, buffer[0], BUFFER_SIZE, &fft, &fft_size);

		if (fft_size == 0) return;

		float freq      = 0.f;
		float freq_step = (float)m_samplerate / (float)fft_size;
		int   band      = 0;

		for (float& b : m_bands) b = 0;

		for (int i = 0; i < fft_size; ++i, freq += freq_step) {


			if (freq > m_band_frequencies[band]) {
				band = qMin(band + 1, m_bands.length() - 1);
			}

			if (fft[i] > m_bands[band]) m_bands[band] = fft[i];
		}

		//m_bars.append(peak);

		this->repaint();
	}

protected:
	void paintEvent(QPaintEvent *event) override {
		QSize content_size = QSize(400, 200);

		int bar_width = content_size.width() / m_bands.length();

		QPainter painter(this);

		painter.setBrush(QBrush(Qt::red));
		
		int x_offset = 0;

		for (float bar : m_bands) {
			QRect rect(x_offset, 0, bar_width, (int)(bar * content_size.height()));
			painter.drawRect(rect);
			x_offset += bar_width;
		}
	}
};
