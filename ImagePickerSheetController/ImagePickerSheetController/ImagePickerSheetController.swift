//
//  ImagePickerController.swift
//  ImagePickerSheet
//
//  Created by Laurin Brandner on 24/05/15.
//  Copyright (c) 2015 Laurin Brandner. All rights reserved.
//

import Foundation
import Photos

private let collectionViewInset: CGFloat = 5
private let collectionViewCheckmarkInset: CGFloat = 3.5

@available(iOS 8.0, *)
public class ImagePickerSheetController: UIViewController {
    
    private lazy var sheetController: SheetController = {
        let layout = SheetCollectionViewLayout()
        let collectionView = UICollectionView(frame: CGRect(), collectionViewLayout: layout)
        collectionView.accessibilityIdentifier = "ImagePickerSheet"
        collectionView.backgroundColor = .clearColor()
        collectionView.alwaysBounceVertical = false
        collectionView.registerClass(SheetPreviewCollectionViewCell.self, forCellWithReuseIdentifier: NSStringFromClass(SheetPreviewCollectionViewCell.self))
        collectionView.registerClass(SheetActionCollectionViewCell.self, forCellWithReuseIdentifier: NSStringFromClass(SheetActionCollectionViewCell.self))
        
        let controller = SheetController(sheetCollectionView: collectionView, previewCollectionView: self.previewCollectionView)
        collectionView.dataSource = controller
        collectionView.delegate = controller
        
        return controller
    }()
    
    var sheetCollectionView: UICollectionView {
        return sheetController.sheetCollectionView
    }
    
    private(set) lazy var previewCollectionView: PreviewCollectionView = {
        let collectionView = PreviewCollectionView()
        collectionView.accessibilityIdentifier = "ImagePickerSheetPreview"
        collectionView.backgroundColor = .clearColor()
        collectionView.allowsMultipleSelection = true
        collectionView.imagePreviewLayout.sectionInset = UIEdgeInsetsMake(collectionViewInset, collectionViewInset, collectionViewInset, collectionViewInset)
        collectionView.imagePreviewLayout.showsSupplementaryViews = false
        collectionView.dataSource = self
        collectionView.delegate = self
        collectionView.showsHorizontalScrollIndicator = false
        collectionView.alwaysBounceHorizontal = true
        collectionView.registerClass(PreviewCollectionViewCell.self, forCellWithReuseIdentifier: NSStringFromClass(PreviewCollectionViewCell.self))
        collectionView.registerClass(PreviewSupplementaryView.self, forSupplementaryViewOfKind: UICollectionElementKindSectionHeader, withReuseIdentifier: NSStringFromClass(PreviewSupplementaryView.self))
        
        return collectionView
    }()
    
    lazy var backgroundView: UIView = {
        let view = UIView()
        view.accessibilityIdentifier = "ImagePickerSheetBackground"
        view.backgroundColor = UIColor(white: 0.0, alpha: 0.3961)
        view.addGestureRecognizer(UITapGestureRecognizer(target: self, action: "cancel"))
        
        return view
    }()
    
    /// All the actions. The first action is shown at the top.
    public var actions: [ImagePickerAction] {
        return sheetController.actions
    }
    
    /// Maximum selection of images.
    public var maximumSelection: Int?
    
    private var assets = [PHAsset]()
    
    private var selectedImageIndices = [Int]()
    
    /// The number of the currently selected images.
    public var numberOfSelectedImages: Int {
        return selectedImageIndices.count
    }
    
    /// The selected image assets
    public var selectedImageAssets: [PHAsset] {
        return selectedImageIndices.map { self.assets[$0] }
    }
    
    /// Whether the preview row has been elarged. This is the case when at least once
    /// image has been selected.
    public private(set) var enlargedPreviews = false
    
    private var supplementaryViews = [Int: PreviewSupplementaryView]()
    
    private let imageManager = PHCachingImageManager()
    
    // MARK: - Initialization
    
    override init(nibName nibNameOrNil: String?, bundle nibBundleOrNil: NSBundle?) {
        super.init(nibName: nibNameOrNil, bundle: nibBundleOrNil)
        initialize()
    }

    required public init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        initialize()
    }
    
    private func initialize() {
        modalPresentationStyle = .Custom
        transitioningDelegate = self
    }
    
    // MARK: - View Lifecycle
    
    override public func loadView() {
        super.loadView()
        
        view.addSubview(backgroundView)
        view.addSubview(sheetCollectionView)
    }
    
    public override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)
        
        preferredContentSize = CGSize(width: 400, height: view.frame.height)
        
        if PHPhotoLibrary.authorizationStatus() == .Authorized {
            fetchAssets()
        }
    }
    
    public override func viewDidAppear(animated: Bool) {
        super.viewDidAppear(animated)
        
        if PHPhotoLibrary.authorizationStatus() == .NotDetermined {
            PHPhotoLibrary.requestAuthorization() { status in
                if status == .Authorized {
                    dispatch_async(dispatch_get_main_queue()) {
                        self.fetchAssets()
                        
                        self.sheetCollectionView.reloadData()
                        self.view.setNeedsLayout()
                        
                        // Explicitely disable animations so it wouldn't animate either
                        // if it was in a popover
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        self.view.layoutIfNeeded()
                        CATransaction.commit()
                    }
                }
            }
        }
    }
    
    // MARK: - Actions
    
    /// Adds an new action.
    /// If the passed action is of type Cancel, any pre-existing Cancel actions will be removed.
    /// Always arranges the actions so that the Cancel action appears at the bottom.
    public func addAction(action: ImagePickerAction) {
        sheetController.addAction(action)
    }
    
    @objc private func cancel() {
        presentingViewController?.dismissViewControllerAnimated(true, completion: nil)
        
        let cancelActions = actions.filter { $0.style == ImagePickerActionStyle.Cancel }
        if let cancelAction = cancelActions.first {
            cancelAction.handle(numberOfSelectedImages)
        }
    }
    
    // MARK: - Images
    
    private func sizeForAsset(asset: PHAsset) -> CGSize {
        let proportion = CGFloat(asset.pixelWidth)/CGFloat(asset.pixelHeight)
        
        let maxImageSize = CGSize(width: sheetController.preferredSheetWidth - 2 * collectionViewInset,
                                 height: sheetController.imagePreviewHeight - 2 * collectionViewInset)
        
        var width = floor(proportion*maxImageSize.height)
        if enlargedPreviews {
            width = min(width, maxImageSize.width)
        }
        
        return CGSize(width: width, height: maxImageSize.height)
    }
    
    private func targetSizeForAssetOfSize(size: CGSize) -> CGSize {
        let scale = UIScreen.mainScreen().scale
        return CGSize(width: scale*size.width, height: scale*size.height)
    }
    
    private func fetchAssets() {
        let options = PHFetchOptions()
        options.sortDescriptors = [NSSortDescriptor(key: "creationDate", ascending: false)]
        let result = PHAsset.fetchAssetsWithMediaType(.Image, options: options)
        
        result.enumerateObjectsUsingBlock { obj, _, _ in
            if let asset = obj as? PHAsset where self.assets.count < 50 {
                self.assets.append(asset)
            }
        }
    }
    
    private func requestImageForAsset(asset: PHAsset, size: CGSize? = nil, deliveryMode: PHImageRequestOptionsDeliveryMode = .Opportunistic, completion: (image: UIImage?) -> Void) {
        var targetSize = PHImageManagerMaximumSize
        if let size = size {
            targetSize = targetSizeForAssetOfSize(size)
        }
        
        let options = PHImageRequestOptions()
        options.deliveryMode = deliveryMode;
        
        // Workaround because PHImageManager.requestImageForAsset doesn't work for burst images
        if asset.representsBurst {
            imageManager.requestImageDataForAsset(asset, options: options) { data, _, _, _ in
                let image = data.flatMap { UIImage(data: $0) }
                completion(image: image)
            }
        }
        else {
            imageManager.requestImageForAsset(asset, targetSize: targetSize, contentMode: .AspectFill, options: options) { image, _ in
                completion(image: image)
            }
        }
    }
    
    private func prefetchImagesForAsset(asset: PHAsset, size: CGSize) {
        // Not necessary to cache image because PHImageManager won't return burst images
        if !asset.representsBurst {
            let targetSize = targetSizeForAssetOfSize(size)
            imageManager.startCachingImagesForAssets([asset], targetSize: targetSize, contentMode: .AspectFill, options: nil)
        }
    }
    
    // MARK: - Layout
    
    public override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        
        reloadImagePreviewHeight()
        
        backgroundView.frame = view.bounds
        sheetCollectionView.frame = view.bounds
        
        let sheetHeight = sheetController.preferredSheetHeight
        let sheetSize = CGSize(width: view.bounds.width, height: sheetHeight)
        
        // This particular order is necessary so that the sheet is layed out
        // correctly with and without an enclosing popover
        preferredContentSize = sheetSize
        sheetCollectionView.frame = CGRect(origin: CGPoint(x: view.bounds.minX, y: view.bounds.maxY-sheetHeight), size: sheetSize)
    }
    
    private func reloadImagePreviewHeight() {
        guard assets.count > 0 else {
            sheetController.imagePreviewHeight = 0
            return
        }
        
        let minHeight: CGFloat = 129
        
        guard enlargedPreviews else {
            sheetController.imagePreviewHeight = minHeight
            return
        }
        
        let maxHeight: CGFloat = 300
        let maxImageWidth = view.bounds.width - 2 * collectionViewInset

        let assetRatios = assets.map { CGSize(width: max($0.pixelHeight, $0.pixelWidth), height: min($0.pixelHeight, $0.pixelWidth)) }
                                .map { $0.height / $0.width }
            
        let assetHeights = assetRatios.map { $0 * maxImageWidth }
                                      .filter { $0 < maxImageWidth && $0 < maxHeight } // Make sure the preview isn't too high eg for squares
                                      .sort(>)
        let assetHeight = round(assetHeights.first ?? 0)
        
        // Just a sanity check, to make sure this doesn't exceed 300 points
        let scaledHeight = max(min(assetHeight, maxHeight), 200)
        sheetController.imagePreviewHeight = scaledHeight + 2 * collectionViewInset
    }

}

// MARK: - UICollectionViewDataSource

extension ImagePickerSheetController: UICollectionViewDataSource {
    
    public func numberOfSectionsInCollectionView(collectionView: UICollectionView) -> Int {
        return assets.count
    }
    
    public func collectionView(collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        return 1
    }
    
    public func collectionView(collectionView: UICollectionView, cellForItemAtIndexPath indexPath: NSIndexPath) -> UICollectionViewCell {
        let cell = collectionView.dequeueReusableCellWithReuseIdentifier(NSStringFromClass(PreviewCollectionViewCell.self), forIndexPath: indexPath) as! PreviewCollectionViewCell
        
        let asset = assets[indexPath.section]
        let size = sizeForAsset(asset)
        
        requestImageForAsset(asset, size: size) { image in
            cell.imageView.image = image
        }
        
        cell.selected = selectedImageIndices.contains(indexPath.section)
        
        return cell
    }
    
    public func collectionView(collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, atIndexPath indexPath:
        NSIndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryViewOfKind(UICollectionElementKindSectionHeader, withReuseIdentifier: NSStringFromClass(PreviewSupplementaryView.self), forIndexPath: indexPath) as! PreviewSupplementaryView
        view.userInteractionEnabled = false
        view.buttonInset = UIEdgeInsetsMake(0.0, collectionViewCheckmarkInset, collectionViewCheckmarkInset, 0.0)
        view.selected = selectedImageIndices.contains(indexPath.section)
        
        supplementaryViews[indexPath.section] = view
        
        return view
    }
    
}

// MARK: - UICollectionViewDelegate

extension ImagePickerSheetController: UICollectionViewDelegate {
    
    public func collectionView(collectionView: UICollectionView, willDisplayCell cell: UICollectionViewCell, forItemAtIndexPath indexPath: NSIndexPath) {
        let nextIndex = indexPath.row+1
        if nextIndex < assets.count {
            let asset = assets[nextIndex]
            let size = sizeForAsset(asset)
            
            self.prefetchImagesForAsset(asset, size: size)
        }
    }
    
    public func collectionView(collectionView: UICollectionView, didSelectItemAtIndexPath indexPath: NSIndexPath) {
        if let maximumSelection = maximumSelection {
            if selectedImageIndices.count >= maximumSelection,
                let previousItemIndex = selectedImageIndices.first {
                    supplementaryViews[previousItemIndex]?.selected = false
                    selectedImageIndices.removeAtIndex(0)
            }
        }
        
        selectedImageIndices.append(indexPath.section)
        
        if !enlargedPreviews {
            enlargedPreviews = true
            
            previewCollectionView.imagePreviewLayout.invalidationCenteredIndexPath = indexPath
            
            view.setNeedsLayout()
            reloadImagePreviewHeight()
            UIView.animateWithDuration(0.3, animations: {
                self.sheetCollectionView.reloadSections(NSIndexSet(index: 0))
                self.view.layoutIfNeeded()
            }, completion: { finished in
                self.sheetController.reloadActionItems()
                self.previewCollectionView.imagePreviewLayout.showsSupplementaryViews = true
            })
        }
        else {
            if let cell = collectionView.cellForItemAtIndexPath(indexPath) {
                var contentOffset = CGPointMake(cell.frame.midX - collectionView.frame.width / 2.0, 0.0)
                contentOffset.x = max(contentOffset.x, -collectionView.contentInset.left)
                contentOffset.x = min(contentOffset.x, collectionView.contentSize.width - collectionView.frame.width + collectionView.contentInset.right)
                
                collectionView.setContentOffset(contentOffset, animated: true)
            }
            
            sheetController.reloadActionItems()
        }
        
        supplementaryViews[indexPath.section]?.selected = true
    }
    
    public func collectionView(collectionView: UICollectionView, didDeselectItemAtIndexPath indexPath: NSIndexPath) {
        if let index = selectedImageIndices.indexOf(indexPath.section) {
            selectedImageIndices.removeAtIndex(index)
            sheetController.reloadActionItems()
        }
        
        supplementaryViews[indexPath.section]?.selected = false
    }
    
}

// MARK: - UICollectionViewDelegateFlowLayout

extension ImagePickerSheetController: UICollectionViewDelegateFlowLayout {
    
    public func collectionView(collectionView: UICollectionView, layout: UICollectionViewLayout, sizeForItemAtIndexPath indexPath: NSIndexPath) -> CGSize {
        return sizeForAsset(assets[indexPath.section])
    }
//
//    public func collectionView(collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
//        let inset = 2.0 * collectionViewCheckmarkInset
//        let size = self.collectionView(collectionView, layout: collectionViewLayout, sizeForItemAtIndexPath: NSIndexPath(forRow: 0, inSection: section))
//        let imageWidth = PreviewSupplementaryView.checkmarkImage?.size.width ?? 0
//        
//        return CGSizeMake(imageWidth  + inset, size.height)
//    }
    
}

// MARK: - UIViewControllerTransitioningDelegate

extension ImagePickerSheetController: UIViewControllerTransitioningDelegate {
    
    public func animationControllerForPresentedController(presented: UIViewController, presentingController presenting: UIViewController, sourceController source: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: true)
    }
    
    public func animationControllerForDismissedController(dismissed: UIViewController) -> UIViewControllerAnimatedTransitioning? {
        return AnimationController(imagePickerSheetController: self, presenting: false)
    }
    
}
