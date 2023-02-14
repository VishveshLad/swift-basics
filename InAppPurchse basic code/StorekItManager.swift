import UIKit
import StoreKit

extension SKProduct {
    var localizedPrice: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.locale = priceLocale
        return formatter.string(from: price)!
    }
}

class InAppPurchaseManager: NSObject {
    
    static let shared = InAppPurchaseManager()
    
    let productIDs: Set<String> = ["com.example.app.product1", "com.example.app.product2"]
    var products: [SKProduct] = []
    var paymentQueue = SKPaymentQueue.default()
    
    private override init() {
        super.init()
        paymentQueue.add(self)
    }
    
    func requestProducts() {
        let request = SKProductsRequest(productIdentifiers: productIDs)
        request.delegate = self
        request.start()
    }
    
    func purchase(product: SKProduct) {
        let payment = SKPayment(product: product)
        paymentQueue.add(payment)
    }
    
    func restorePurchases() {
        paymentQueue.restoreCompletedTransactions()
    }
    
    func verifyReceipt(completion: @escaping (Bool) -> Void) {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            completion(false)
            return
        }
        let receiptData = try? Data(contentsOf: receiptURL)
        guard let base64EncodedReceipt = receiptData?.base64EncodedString() else {
            completion(false)
            return
        }
        let request = NSMutableURLRequest(url: URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")!)
        request.httpMethod = "POST"
        request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        let payload: [String: Any] = ["receipt-data": base64EncodedReceipt]
//        let payload: [String: Any] = ["receipt-data": base64EncodedReceipt, "password": "your-shared-secret"] // if password required use this once
        let payloadData = try! JSONSerialization.data(withJSONObject: payload, options: [])
        request.httpBody = payloadData
        let session = URLSession.shared
        let task = session.dataTask(with: request as URLRequest, completionHandler: { (data, response, error) in
            if let data = data, let response = response as? HTTPURLResponse, response.statusCode == 200 {
                do {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as! [String: Any]
                    if let status = jsonResponse["status"] as? Int, status == 0 {
                        completion(true)
                    } else {
                        completion(false)
                    }
                } catch {
                    completion(false)
                }
            } else {
                completion(false)
            }
        })
        task.resume()
    }
}

extension InAppPurchaseManager: SKProductsRequestDelegate {
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        products = response.products
        for product in products {
            print("Found product: \(product.localizedTitle) \(product.localizedPrice)")
        }
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        print("Failed to load list of products: \(error.localizedDescription)")
    }
}

extension InAppPurchaseManager: SKPaymentTransactionObserver {
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                completeTransaction(transaction)
            case .restored:
                completeTransaction(transaction)
            case .failed:
                failedTransaction(transaction)
            case .deferred, .purchasing:
                break
            default:
                break
            }
        }
    }
    
    private func completeTransaction(_ transaction: SKPaymentTransaction) {
        guard let productID = transaction.payment.productIdentifier else {
            return
        }
        SKPaymentQueue.default().finishTransaction(transaction)
    }
}


import StoreKit

class InAppPurchaseManager: NSObject, SKProductsRequestDelegate, SKPaymentTransactionObserver {
    
    static let shared = InAppPurchaseManager()
    
    var productsRequest: SKProductsRequest?
    var products = [SKProduct]()
    var productIdentifiers = Set<String>()
    var productRequestCompletionHandler: ((Bool, [SKProduct]?) -> Void)?
    var purchaseCompletionHandler: ((Bool) -> Void)?
    
    private override init() {
        super.init()
        SKPaymentQueue.default().add(self)
    }
    
    func getProducts(productIdentifiers: Set<String>, completionHandler: @escaping (Bool, [SKProduct]?) -> Void) {
        products.removeAll()
        self.productIdentifiers = productIdentifiers
        self.productRequestCompletionHandler = completionHandler
        
        productsRequest = SKProductsRequest(productIdentifiers: productIdentifiers)
        productsRequest?.delegate = self
        productsRequest?.start()
    }
    
    func purchase(product: SKProduct, completionHandler: @escaping (Bool) -> Void) {
        guard SKPaymentQueue.canMakePayments() else {
            completionHandler(false)
            return
        }
        
        purchaseCompletionHandler = completionHandler
        
        let payment = SKPayment(product: product)
        SKPaymentQueue.default().add(payment)
    }
    
    // MARK: - SKProductsRequestDelegate
    
    func productsRequest(_ request: SKProductsRequest, didReceive response: SKProductsResponse) {
        productsRequest = nil
        
        let products = response.products
        
        productRequestCompletionHandler?(true, products)
        productRequestCompletionHandler = nil
    }
    
    func request(_ request: SKRequest, didFailWithError error: Error) {
        productsRequest = nil
        
        productRequestCompletionHandler?(false, nil)
        productRequestCompletionHandler = nil
    }
    
    // MARK: - SKPaymentTransactionObserver
    
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                complete(transaction: transaction)
            case .failed:
                fail(transaction: transaction)
            case .restored:
                restore(transaction: transaction)
            case .deferred, .purchasing:
                break
            @unknown default:
                break
            }
        }
    }
    
    func complete(transaction: SKPaymentTransaction) {
        deliverPurchaseNotification(for: transaction.payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
        purchaseCompletionHandler?(true)
    }
    
    func fail(transaction: SKPaymentTransaction) {
        if let error = transaction.error as? SKError, error.code != .paymentCancelled {
            print("Transaction failed with error: \(error.localizedDescription)")
        }
        SKPaymentQueue.default().finishTransaction(transaction)
        purchaseCompletionHandler?(false)
    }
    
    func restore(transaction: SKPaymentTransaction) {
        deliverPurchaseNotification(for: transaction.payment.productIdentifier)
        SKPaymentQueue.default().finishTransaction(transaction)
        purchaseCompletionHandler?(true)
    }
    
    func deliverPurchaseNotification(for identifier: String?) {
        guard let identifier = identifier else { return }
        NotificationCenter.default.post(name: .IAPManagerPurchaseNotification, object: identifier)
    }
}

extension InAppPurchaseManager {
    
    func restorePurchases(completionHandler: @escaping (Bool) -> Void) {
        purchaseCompletionHandler = completionHandler
        SKPaymentQueue.default().restoreCompletedTransactions()
    }
    
    func verifyReceipt(completionHandler: @escaping (Bool) -> Void) {
        guard let receiptURL = Bundle.main.appStoreReceiptURL else {
            completionHandler(false)
            return
        }
        
        do {
            let receiptData = try Data(contentsOf: receiptURL)
            let receiptString = receiptData.base64EncodedString(options: [])
            let requestData = ["receipt-data" : receiptString]
            let requestJSON = try JSONSerialization.data(withJSONObject: requestData, options: [])
            
            let url = URL(string: "https://sandbox.itunes.apple.com/verifyReceipt")! // Change to production URL for production app
            
            var request = URLRequest(url: url)
            request.httpMethod = "POST"
            request.httpBody = requestJSON
            
            let task = URLSession.shared.dataTask(with: request) { data, response, error in
                if let error = error {
                    print("Receipt verification failed with error: \(error.localizedDescription)")
                    completionHandler(false)
                    return
                }
                
                guard let data = data else {
                    completionHandler(false)
                    return
                }
                
                do {
                    let jsonResponse = try JSONSerialization.jsonObject(with: data, options: []) as? [String: Any]
                    guard let status = jsonResponse?["status"] as? Int, status == 0 else {
                        completionHandler(false)
                        return
                    }
                    
                    completionHandler(true)
                } catch {
                    print("Receipt verification failed with error: \(error.localizedDescription)")
                    completionHandler(false)
                }
            }
            
            task.resume()
        } catch {
            print("Receipt verification failed with error: \(error.localizedDescription)")
            completionHandler(false)
        }
    }
}

import StoreKit

class ViewController {
    
    let inAppPurchaseManager = InAppPurchaseManager.shared
    
    var products: [SKProduct] = []


    // request product
    inAppPurchaseManager.requestProducts { products in
        self.products = products
        // Update your UI to display the available products
    }

    // purchase flow while user click on purchase button
    guard let product = products.first(where: { $0.productIdentifier == "com.example.product" }) else {
        return
    }
    
    let payment = SKPayment(product: product)

    SKPaymentQueue.default().add(payment)

    
    
    
    // restore purchases
    inAppPurchaseManager.restorePurchases { success in
        if success {
            // Purchases were successfully restored
        } else {
            // Purchase restore failed
        }
    }

    // verify receipt
    inAppPurchaseManager.verifyReceipt { success in
        if success {
            // Receipt verification succeeded
        } else {
            // Receipt verification failed
        }
    }

}


class ViewController: UIViewController, SKPaymentTransactionObserver {
    
    // Implement the SKPaymentTransactionObserver protocol methods here
    func paymentQueue(_ queue: SKPaymentQueue, updatedTransactions transactions: [SKPaymentTransaction]) {
        for transaction in transactions {
            switch transaction.transactionState {
            case .purchased:
                // Handle the purchase here
                inAppPurchaseManager.verifyReceipt { success in
                    if success {
                        // Receipt verification succeeded
                    } else {
                        // Receipt verification failed
                    }
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            case .failed:
                // Handle the transaction failure here
                SKPaymentQueue.default().finishTransaction(transaction)
            case .restored:
                // Handle the restored transaction here
                inAppPurchaseManager.verifyReceipt { success in
                    if success {
                        // Receipt verification succeeded
                    } else {
                        // Receipt verification failed
                    }
                }
                SKPaymentQueue.default().finishTransaction(transaction)
            default:
                break
            }
        }
    }
    
    // The rest of your view controller implementation here
    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        SKPaymentQueue.default().remove(self)
    }

}


/*
 Yes, there are a few additional things you need to do to complete the implementation of in-app purchases in your app:

 Set up your in-app purchases and associated products in App Store Connect.

 Add the appropriate code to handle purchases and restore purchases in your app. This may involve creating an interface for users to initiate purchases, handling payment transactions, and providing feedback to users about the success or failure of their purchases.

 Test your in-app purchases in a sandbox environment before submitting your app to the App Store. You can create a test user account in App Store Connect to test the purchase flow without actually spending any money.

 Follow Apple's guidelines and best practices for in-app purchases, including displaying clear and accurate pricing information, providing a way for users to easily restore their purchases, and avoiding misleading or fraudulent practices.

 By following these steps and thoroughly testing your in-app purchase implementation, you can ensure a smooth and reliable purchase experience for your users.
 */
