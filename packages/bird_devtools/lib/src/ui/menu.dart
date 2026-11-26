// The menus live in bird_ui. Under a DevToolsScope they are the compact ones,
// in the tools' own colours.
import 'package:bird_ui/bird_ui.dart';

export 'package:bird_ui/bird_ui.dart' show BirdMenuEntry, BirdMenuItem;

typedef DtMenuEntry = BirdMenuEntry;
typedef DtMenuItem = BirdMenuItem;

const showDtMenu = showBirdMenu;
const showDtMenuBelow = showBirdMenuBelow;
