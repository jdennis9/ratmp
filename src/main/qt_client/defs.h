#pragma once

#include <QString>
#include <string.h>
#include "../c_interface/c_interface.h"

static inline QString to_qstring(RATMP_String str) {
	return QString::fromUtf8(
		QByteArrayView(str.data, (qsizetype)str.len)
	);
}

static inline RATMP_String from_cstring(const char *s) {
	RATMP_String str;
	str.data = s;
	str.len = strlen(s);
	return str;
}

static inline void seconds_to_hms(int seconds, int& h, int& m, int& s) {
	h = seconds / 3600;
	m = (seconds / 60) - (h * 60);
	s = seconds - (h * 3600) - (m * 60);
}
