/// The keywords completed for the values of common properties.
const List<String> cssGlobalKeywords = ['inherit', 'initial', 'revert', 'unset'];

const String _lineStyles = 'none solid dashed dotted double groove ridge inset outset hidden';
const String _alignment = 'normal stretch center start end flex-start flex-end self-start self-end baseline';
const String _distribution = 'normal flex-start flex-end start end center space-between space-around space-evenly stretch';
const String _sizing = 'auto min-content max-content fit-content';
const String _cursors = 'auto default none pointer wait help text crosshair move not-allowed grab grabbing zoom-in zoom-out col-resize row-resize ew-resize ns-resize';

const Map<String, String> _keywords = {
  'display': 'block inline inline-block flex inline-flex grid inline-grid none contents flow-root table table-row table-cell list-item',
  'position': 'static relative absolute fixed sticky',
  'float': 'none left right inline-start inline-end',
  'clear': 'none left right both inline-start inline-end',
  'visibility': 'visible hidden collapse',
  'overflow': 'visible hidden clip scroll auto',
  'overflow-x': 'visible hidden clip scroll auto',
  'overflow-y': 'visible hidden clip scroll auto',
  'box-sizing': 'content-box border-box',
  'flex-direction': 'row row-reverse column column-reverse',
  'flex-wrap': 'nowrap wrap wrap-reverse',
  'justify-content': _distribution,
  'align-content': _distribution,
  'align-items': _alignment,
  'align-self': 'auto $_alignment',
  'justify-items': _alignment,
  'justify-self': 'auto $_alignment',
  'text-align': 'start end left right center justify match-parent',
  'text-decoration': 'none underline overline line-through',
  'text-transform': 'none capitalize uppercase lowercase full-width',
  'text-overflow': 'clip ellipsis',
  'white-space': 'normal nowrap pre pre-wrap pre-line break-spaces',
  'word-break': 'normal break-all keep-all break-word',
  'overflow-wrap': 'normal break-word anywhere',
  'font-weight': 'normal bold bolder lighter 100 200 300 400 500 600 700 800 900',
  'font-style': 'normal italic oblique',
  'font-family': 'serif sans-serif monospace cursive fantasy system-ui ui-monospace ui-serif ui-sans-serif',
  'font-size': 'xx-small x-small small medium large x-large xx-large smaller larger',
  'cursor': _cursors,
  'pointer-events': 'auto none',
  'user-select': 'auto text none all contain',
  'border-style': _lineStyles,
  'border-top-style': _lineStyles,
  'border-right-style': _lineStyles,
  'border-bottom-style': _lineStyles,
  'border-left-style': _lineStyles,
  'outline-style': 'auto $_lineStyles',
  'background-repeat': 'repeat no-repeat repeat-x repeat-y space round',
  'background-size': 'auto cover contain',
  'background-position': 'center top bottom left right',
  'background-attachment': 'scroll fixed local',
  'object-fit': 'fill contain cover none scale-down',
  'vertical-align': 'baseline top middle bottom sub super text-top text-bottom',
  'list-style-type': 'none disc circle square decimal lower-alpha upper-alpha lower-roman upper-roman',
  'grid-auto-flow': 'row column dense',
  'width': _sizing,
  'height': _sizing,
  'min-width': _sizing,
  'min-height': _sizing,
  'max-width': 'none min-content max-content fit-content',
  'max-height': 'none min-content max-content fit-content',
  'margin': 'auto',
  'table-layout': 'auto fixed',
  'border-collapse': 'collapse separate',
  'resize': 'none both horizontal vertical',
  'direction': 'ltr rtl',
  'mix-blend-mode': 'normal multiply screen overlay darken lighten color-dodge color-burn difference exclusion',
  'appearance': 'none auto',
};

bool takesColor(String property) =>
    property == 'color' ||
    property.endsWith('-color') ||
    const {'background', 'border', 'outline', 'box-shadow', 'text-shadow', 'fill', 'stroke', 'border-top', 'border-right', 'border-bottom', 'border-left', 'text-decoration'}.contains(property);

List<String> keywordsFor(String property) => [
  ...?_keywords[property]?.split(' '),
  if (takesColor(property)) ...['transparent', 'currentcolor'],
  ...cssGlobalKeywords,
];
