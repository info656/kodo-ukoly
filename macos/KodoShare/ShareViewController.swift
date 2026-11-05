import Cocoa
import UniformTypeIdentifiers

// URL/text only. No attachments, authentication tokens or database access.
@objc(ShareViewController)
class ShareViewController: NSViewController {
  private let status=NSTextField(labelWithString:"Odkaz nebo text přidáte do Inboxu v Kodo Úkoly.")
  override func loadView() {
    view=NSView(frame:NSRect(x:0,y:0,width:360,height:130))
    status.frame=NSRect(x:20,y:70,width:320,height:40);status.lineBreakMode = .byWordWrapping
    let button=NSButton(title:"Přidat do Inboxu",target:self,action:#selector(send))
    button.frame=NSRect(x:170,y:20,width:170,height:32)
    let cancel=NSButton(title:"Zrušit",target:self,action:#selector(cancelShare));cancel.frame=NSRect(x:20,y:20,width:90,height:32)
    view.addSubview(status);view.addSubview(button);view.addSubview(cancel)
  }
  @objc func cancelShare(){extensionContext?.completeRequest(returningItems:nil)}
  @objc func send(){
    let items=extensionContext?.inputItems as? [NSExtensionItem] ?? []
    let providers=items.flatMap{$0.attachments ?? []}
    guard let provider=providers.first(where:{$0.hasItemConformingToTypeIdentifier(UTType.url.identifier)||$0.hasItemConformingToTypeIdentifier(UTType.plainText.identifier)}) else {status.stringValue="Vyberte odkaz nebo text.";return}
    let type=provider.hasItemConformingToTypeIdentifier(UTType.url.identifier) ? UTType.url.identifier : UTType.plainText.identifier
    provider.loadItem(forTypeIdentifier:type,options:nil){[weak self] value,error in
      DispatchQueue.main.async {
        guard let self=self,error==nil else{return}
        let text=(value as? URL)?.absoluteString ?? (value as? String) ?? ""
        guard !text.isEmpty,text.count<=15000 else{self.status.stringValue="Text je prázdný nebo příliš dlouhý.";return}
        if let url=URL(string:text),let scheme=url.scheme,!(["http","https"].contains(scheme.lowercased())){self.status.stringValue="Podporujeme webové odkazy HTTP a HTTPS.";return}
        var parts=URLComponents();parts.scheme="kodoukoly";parts.host="share"
        parts.queryItems=[URLQueryItem(name:"text",value:text),URLQueryItem(name:"title",value:items.first?.attributedTitle?.string ?? "")]
        guard let url=parts.url,NSWorkspace.shared.open(url) else{self.status.stringValue="Nejprve spusťte Kodo Úkoly.";return}
        self.extensionContext?.completeRequest(returningItems:nil)
      }
    }
  }
}
