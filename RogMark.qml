import QtQuick
import QtQuick.Shapes
import qs.Commons

// The ROG wordmark — the angular, italic "ROG" lettering ASUS uses on the
// Zephyrus lid, not the Mayan-eye mark.
//
// Drawn as vector paths rather than a font glyph or an SVG file for the same
// reasons omarchy draws its own Dropbox logo this way: it tints with the
// theme foreground, stays sharp at any bar size, and adds no image asset that
// could go missing. Geometry is authored upright in a 252x100 box and sheared
// into its italic by the matrix below, so the letterforms stay easy to edit.
Item {
  id: root

  property real markHeight: Style.font.icon
  property color color: Color.foreground

  // 252 wide upright + 20 of shear travel at the top edge.
  readonly property real designWidth: 272
  readonly property real designHeight: 100

  implicitWidth: markHeight * (designWidth / designHeight)
  implicitHeight: markHeight
  width: implicitWidth
  height: implicitHeight

  Item {
    width: root.designWidth
    height: root.designHeight
    anchors.centerIn: parent
    scale: root.markHeight / root.designHeight
    transformOrigin: Item.Center

    Shape {
      anchors.fill: parent
      antialiasing: true
      layer.enabled: true
      layer.samples: 4
      preferredRendererType: Shape.CurveRenderer

      // x' = x - 0.2y + 20 : leans the whole lockup right by ~11 degrees.
      transform: Matrix4x4 {
        matrix: Qt.matrix4x4(1, -0.2, 0, 20,
                             0, 1, 0, 0,
                             0, 0, 1, 0,
                             0, 0, 0, 1)
      }

      // R — chamfered shoulder, straight diagonal leg.
      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        fillRule: ShapePath.OddEvenFill
        PathSvg {
          path: "M0,0 L48,0 L64,16 L64,44 L50,56 L66,100 L40,100 L27,60 L20,60 L20,100 L0,100 Z "
              + "M20,17 L45,17 L45,43 L20,43 Z"
        }
      }

      // O — cut corners top-left and bottom-right, squared counter.
      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        fillRule: ShapePath.OddEvenFill
        PathSvg {
          path: "M78,16 L94,0 L142,0 L158,16 L158,84 L142,100 L94,100 L78,84 Z "
              + "M98,22 L138,22 L138,78 L98,78 Z"
        }
      }

      // G — squared spur into the bowl.
      ShapePath {
        fillColor: root.color
        strokeWidth: 0
        PathSvg {
          path: "M186,0 L238,0 L252,14 L252,28 L232,28 L232,20 L206,20 L206,80 L232,80 "
              + "L232,62 L218,62 L218,44 L252,44 L252,86 L238,100 L186,100 L172,86 L172,14 Z"
        }
      }
    }
  }
}
