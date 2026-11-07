import CoreText
import Foundation

public enum OrbitFonts {
    /// Registers the bundled Inter Tight files. Call once at startup of the app AND the widget extension.
    public static func register() {
        let urls = Bundle.module.urls(forResourcesWithExtension: "ttf", subdirectory: "Fonts") ?? []
        for url in urls {
            // Fails harmlessly if the font is already registered in this process.
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
        }
    }
}
