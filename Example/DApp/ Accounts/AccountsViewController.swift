import UIKit
import WalletConnect

struct AccountDetails {
    let chain: String
    let methods: [String]
    let account: String
}

final class AccountsViewController: UIViewController, UITableViewDataSource, UITableViewDelegate  {
    
    let client = ClientDelegate.shared.client
    let session: Session
    var accountsDetails: [AccountDetails] = []
    var onDisconnect: (()->())?
    
    private let accountsView: AccountsView = {
        AccountsView()
    }()
    
    init(session: Session) {
        self.session = session
        super.init(nibName: nil, bundle: nil)
    }
    
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func loadView() {
        view = accountsView
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        navigationItem.title = "Accounts"
        
        navigationItem.rightBarButtonItem = UIBarButtonItem(
            title: "Disconnect",
            style: .plain,
            target: self,
            action: #selector(disconnect)
        )
        accountsView.tableView.dataSource = self
        accountsView.tableView.delegate = self
        session.accounts.forEach { account in
            accountsDetails.append(AccountDetails(chain: account.blockchainIdentifier, methods: Array(session.permissions.methods), account: account.address))
        }
    }
    
    @objc
    private func disconnect() {
        client.disconnect(topic: session.topic, reason: Reason(code: 0, message: "disconnect"))
        onDisconnect?()
    }
    
    func tableView(_ tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        accountsDetails.count
    }
    
    func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        let cell = tableView.dequeueReusableCell(withIdentifier: "accountCell", for: indexPath)
        let details = accountsDetails[indexPath.row]
        cell.textLabel?.text = details.account
        cell.imageView?.image = UIImage(named: details.chain)
        cell.textLabel?.numberOfLines = 0
        return cell
    }
    
    func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        showAccountRequestScreen(accountsDetails[indexPath.row])
    }
    
    func tableView(_ tableView: UITableView, heightForRowAt indexPath: IndexPath) -> CGFloat {
        return 70
    }
    
    func showAccountRequestScreen(_ details: AccountDetails) {
        let vc = AccountRequestViewController(session: session, accountDetails: details)
        navigationController?.pushViewController(vc, animated: true)
    }
    
}
