import Foundation
import Photos
import OSLog

class CustomPhotoManager: NSObject, PHPhotoLibraryChangeObserver{
    
    enum UserInfoKey: String{
        case authorizationDeniedAlert = "authorizationDeniedAlert"
        case alertTitle = "alertTitle"
        case alertMessage = "alertMessage"
        case actionTitle = "actionTitle"
        case settingActionHandler = "settingActionHandler"
    }
    
    struct NotificationName{
        static let sendPresentingAlertSignal = Notification.Name("sendPresentingAlertSignal")
    }
    
    private var logger: Logger = Logger()
    private let manager = PHCachingImageManager()
    private let option = PHImageRequestOptions()
    private var images: PHAssetCollection?
    private var assets: [PHAsset] = []

    deinit {
        PHPhotoLibrary.shared().unregisterChangeObserver(self)
    }
    
    override init(){
        super.init()
        PHPhotoLibrary.shared().register(self)
        self.option.isSynchronous = true
    }
    
    func getAssetCount()->Int{
        guard let images = self.images else { return 0 }
        return PHAsset.fetchAssets(in: images, options: nil).count
    }
    
    func getAuthorization() {
        if isAlbumAcessAuthorized() {
            self.setAssets()
        } else if isAlbumAccessDenied() {
            self.setAuthAlertAction()
        } else {
            PHPhotoLibrary.requestAuthorization() { (status) in
                self.getAuthorization()
            }
        }
    }
    
    func setAssets(){
        self.assets = fetchAssetCollection()
    }
    
    func fetchAssetCollection() -> [PHAsset] {
        PHAssetCollection.fetchAssetCollections(with: PHAssetCollectionType.smartAlbum, subtype: PHAssetCollectionSubtype.smartAlbumUserLibrary, options: PHFetchOptions()).enumerateObjects { (collection, _, _) in
            self.images = collection
        }
        return self.fetchAsset() ?? []
    }
    
    func fetchAsset() -> [PHAsset]? {
        guard let images = self.images else {
            return nil
        }
        var assets: [PHAsset] = []
        let fetchOptions = PHFetchOptions()
        fetchOptions.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        PHAsset.fetchAssets(in: images, options: fetchOptions).enumerateObjects({ (asset, _, _) in
            assets.append(asset)
        })
        return assets
    }
    
    func requestImageData(index: Int)-> Data?{
        var imageData: Data?
        manager.requestImageDataAndOrientation(for: assets[index], options: option, resultHandler: {(data, _, _, _)-> Void in
            guard let data = data else { return }
            imageData = data
        })
        return imageData
    }
    
    func requestModifyingImageData(index: Int, renderedData: Data?) {
        let asset = assets[index]
    
        asset.requestContentEditingInput(with: nil, completionHandler: { (contentEditingInput, info) in
            let adjData = PHAdjustmentData(formatIdentifier: "codesquad2022.ios.PhotoAlbum", formatVersion: "1.0", data: renderedData!)
            
            let contentOutput = PHContentEditingOutput(contentEditingInput: contentEditingInput!)
            contentOutput.adjustmentData = adjData
            
            do {
                try renderedData?.write(to: contentOutput.renderedContentURL, options: .atomic)
                PHPhotoLibrary.shared().performChanges({
                    let request = PHAssetChangeRequest(for: asset)
                    let isEdited = PHAssetResource.assetResources(for: asset).contains(where: { $0.type == .adjustmentData })
                    if isEdited {
                        request.revertAssetContentToOriginal()
                    } else {
                        request.contentEditingOutput = contentOutput
                    }
                })
            } catch let error {
                self.logger.error("\(error.localizedDescription)")
            }
        })
    }
    
    func isAlbumAcessAuthorized() -> Bool {
        return PHPhotoLibrary.authorizationStatus() == .authorized || PHPhotoLibrary.authorizationStatus() == .limited
    }
    
    func isAlbumAccessDenied() -> Bool {
        return PHPhotoLibrary.authorizationStatus() == .denied
    }
    
    func photoLibraryDidChange(_ changeInstance: PHChange) {
        var userInfo: [UserInfoKey:Any] = [:]
        userInfo[UserInfoKey.alertTitle] = "옵저버가 변화를 감지했습니다!"
        userInfo[UserInfoKey.alertMessage] = "컬렉션뷰를 업데이트합니다."
        userInfo[UserInfoKey.actionTitle] = "OK!"
        userInfo[UserInfoKey.settingActionHandler] = false
        
        NotificationCenter.default.post(name: NotificationName.sendPresentingAlertSignal, object: self, userInfo: userInfo)
    }
    
    func setAuthAlertAction() {
        var userInfo: [UserInfoKey:Any] = [:]
        userInfo[UserInfoKey.alertTitle] = "사진 앨범 권한 요청"
        userInfo[UserInfoKey.alertMessage] = "사진첩 권한을 허용해야만 기능을 사용하실 수 있습니다."
        userInfo[UserInfoKey.actionTitle] = "넵"
        userInfo[UserInfoKey.settingActionHandler] = true
        
        NotificationCenter.default.post(name: NotificationName.sendPresentingAlertSignal, object: self, userInfo: userInfo)
    }
}
