import Foundation

/// Baut das XMP-Metadatenpaket für PDF/A-3b mit der ZUGFeRD/Factur-X-Erweiterung.
enum XMPBuilder {
    static func packet(
        title: String,
        author: String,
        producer: String,
        creatorTool: String,
        date: Date,
        attachmentFileName: String,
        conformanceLevel: String
    ) -> Data {
        let iso = DateFmt.format(date, "yyyy-MM-dd'T'HH:mm:ss", timeZone: DateFmt.utc) + "+00:00"
        let t = XML.escape(title)
        let a = XML.escape(author)
        let p = XML.escape(producer)
        let c = XML.escape(creatorTool)
        let f = XML.escape(attachmentFileName)
        let l = XML.escape(conformanceLevel)

        let xmp = """
        <?xpacket begin="\u{FEFF}" id="W5M0MpCehiHzreSzNTczkc9d"?>
        <x:xmpmeta xmlns:x="adobe:ns:meta/">
          <rdf:RDF xmlns:rdf="http://www.w3.org/1999/02/22-rdf-syntax-ns#">
            <rdf:Description rdf:about="" xmlns:pdfaid="http://www.aiim.org/pdfa/ns/id/">
              <pdfaid:part>3</pdfaid:part>
              <pdfaid:conformance>B</pdfaid:conformance>
            </rdf:Description>
            <rdf:Description rdf:about="" xmlns:dc="http://purl.org/dc/elements/1.1/">
              <dc:title><rdf:Alt><rdf:li xml:lang="x-default">\(t)</rdf:li></rdf:Alt></dc:title>
              <dc:creator><rdf:Seq><rdf:li>\(a)</rdf:li></rdf:Seq></dc:creator>
            </rdf:Description>
            <rdf:Description rdf:about="" xmlns:pdf="http://ns.adobe.com/pdf/1.3/">
              <pdf:Producer>\(p)</pdf:Producer>
            </rdf:Description>
            <rdf:Description rdf:about="" xmlns:xmp="http://ns.adobe.com/xap/1.0/">
              <xmp:CreatorTool>\(c)</xmp:CreatorTool>
              <xmp:CreateDate>\(iso)</xmp:CreateDate>
              <xmp:ModifyDate>\(iso)</xmp:ModifyDate>
              <xmp:MetadataDate>\(iso)</xmp:MetadataDate>
            </rdf:Description>
            <rdf:Description rdf:about="" xmlns:fx="urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#">
              <fx:DocumentType>INVOICE</fx:DocumentType>
              <fx:DocumentFileName>\(f)</fx:DocumentFileName>
              <fx:Version>1.0</fx:Version>
              <fx:ConformanceLevel>\(l)</fx:ConformanceLevel>
            </rdf:Description>
            <rdf:Description rdf:about=""
                xmlns:pdfaExtension="http://www.aiim.org/pdfa/ns/extension/"
                xmlns:pdfaSchema="http://www.aiim.org/pdfa/ns/schema#"
                xmlns:pdfaProperty="http://www.aiim.org/pdfa/ns/property#">
              <pdfaExtension:schemas>
                <rdf:Bag>
                  <rdf:li rdf:parseType="Resource">
                    <pdfaSchema:schema>Factur-X PDFA Extension Schema</pdfaSchema:schema>
                    <pdfaSchema:namespaceURI>urn:factur-x:pdfa:CrossIndustryDocument:invoice:1p0#</pdfaSchema:namespaceURI>
                    <pdfaSchema:prefix>fx</pdfaSchema:prefix>
                    <pdfaSchema:property>
                      <rdf:Seq>
                        <rdf:li rdf:parseType="Resource">
                          <pdfaProperty:name>DocumentFileName</pdfaProperty:name>
                          <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                          <pdfaProperty:category>external</pdfaProperty:category>
                          <pdfaProperty:description>name of the embedded XML invoice file</pdfaProperty:description>
                        </rdf:li>
                        <rdf:li rdf:parseType="Resource">
                          <pdfaProperty:name>DocumentType</pdfaProperty:name>
                          <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                          <pdfaProperty:category>external</pdfaProperty:category>
                          <pdfaProperty:description>INVOICE</pdfaProperty:description>
                        </rdf:li>
                        <rdf:li rdf:parseType="Resource">
                          <pdfaProperty:name>Version</pdfaProperty:name>
                          <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                          <pdfaProperty:category>external</pdfaProperty:category>
                          <pdfaProperty:description>The actual version of the Factur-X XML schema</pdfaProperty:description>
                        </rdf:li>
                        <rdf:li rdf:parseType="Resource">
                          <pdfaProperty:name>ConformanceLevel</pdfaProperty:name>
                          <pdfaProperty:valueType>Text</pdfaProperty:valueType>
                          <pdfaProperty:category>external</pdfaProperty:category>
                          <pdfaProperty:description>The conformance level of the embedded Factur-X data</pdfaProperty:description>
                        </rdf:li>
                      </rdf:Seq>
                    </pdfaSchema:property>
                  </rdf:li>
                </rdf:Bag>
              </pdfaExtension:schemas>
            </rdf:Description>
          </rdf:RDF>
        </x:xmpmeta>
        <?xpacket end="w"?>
        """
        return Data(xmp.utf8)
    }
}
