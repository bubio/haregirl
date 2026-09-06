use os;
use strings;

fn locale_is_japanese(locale: str) bool =
	strings::hasprefix(locale, "ja") || strings::hasprefix(locale, "JA");

fn is_japanese() bool = {
	const names = ["LC_ALL", "LC_MESSAGES", "LANG"]: []str;
	for (let i = 0z; i < len(names); i += 1) {
		const value = match (os::getenv(names[i])) {
		case let value: str => yield value;
		case void => yield "";
		};
		if (len(value) > 0) return locale_is_japanese(value);
	};
	return false;
};

fn msg(english: str, japanese: str) str =
	if (is_japanese()) japanese else english;
