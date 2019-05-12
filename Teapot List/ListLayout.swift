//
//  ListLayout.swift
//  Example Layout
//
//  Created by Steve Brunwasser on 3/28/19.
//  Copyright © 2019 Steve Brunwasser. All rights reserved.
//

import Cocoa

/// An NSCollectionViewLayout that should display items with equal widths from top to bottom.
/// Each item's height should be determined by Auto Layout.
class ListLayout: NSCollectionViewLayout {
    var verticalItemSpacing: CGFloat = 8
    var contentEdgeInsets: NSEdgeInsets = NSEdgeInsets(top: 20, left: 20, bottom: 20, right: 20)
    private var cachedContentBounds: NSRect = .zero
    private var cachedItemAttributes: [IndexPath : NSCollectionViewLayoutAttributes] = [:]

    override var collectionViewContentSize: NSSize {
        guard let collectionView = collectionView else { return .zero }

        // Add up the heights of all cached items.
        let totalItemHeight = cachedItemAttributes.values.reduce(0) { height, attributes in
            return height + attributes.size.height
        }

        // Determine the amount of inter-item spacing.
        let interItemSpacing = CGFloat(cachedItemAttributes.count) * verticalItemSpacing

        // Add up the total spacing from vertical insets.
        let insetSpacing = contentEdgeInsets.top + contentEdgeInsets.bottom

        let totalHeight = totalItemHeight + interItemSpacing + insetSpacing
        return NSSize(width: collectionView.bounds.width, height: totalHeight)
    }

    override func prepare() {
        // Only recaluclate the entire layout when it's cache is empty.
        guard let collectionView = collectionView,
              cachedItemAttributes.isEmpty else { return }
        print("🍋: Preparing layout attributes.")

        // Get the index paths for all items in the collection view.
        let sectionIndices = 0 ..< collectionView.numberOfSections
        let indexPaths = sectionIndices.flatMap { section -> [IndexPath] in
            let numberOfItems = collectionView.numberOfItems(inSection: section)
            return (0 ..< numberOfItems).map { IndexPath(item: $0, section: section) }
        }

        cachedContentBounds = collectionView.bounds

        // Calculate initial layout attributes for each item.
        prepare(sortedItemAttributes: indexPaths.map { indexPath -> NSCollectionViewLayoutAttributes in
            // Create the item's attributes, and add them to the cache.
            let attributes = NSCollectionViewLayoutAttributes(forItemWith: indexPath)
            cachedItemAttributes[indexPath] = attributes
            return attributes
        })
    }

    /// Calculate the layout attributes for each item.
    /// - parameter sortedItemAttributes: The list of layout attributes in order of how they should be displayed
    ///                                   in the collection view from top to bottom.
    private func prepare(sortedItemAttributes: [NSCollectionViewLayoutAttributes]) {
        // The width of each item in the collection view.
        let width = cachedContentBounds.width - contentEdgeInsets.left - contentEdgeInsets.right

        // The origin point for the first (top-most) item in the collection view.
        let origin = NSPoint(x: contentEdgeInsets.left, y: contentEdgeInsets.top)

        _ = sortedItemAttributes.reduce(origin) { origin, attributes in
            // Determine the item's size with an "estimated" height value.
            let size = NSSize(width: width, height: 100)

            attributes.frame = NSRect(origin: origin, size: size)

            // Get the origin point for the next item in the collection view.
            return NSPoint(x: origin.x, y: origin.y + size.height + verticalItemSpacing)
        }
    }
}

extension ListLayout {
    override func layoutAttributesForItem(at indexPath: IndexPath) -> NSCollectionViewLayoutAttributes? {
        return cachedItemAttributes[indexPath]
    }

    override func layoutAttributesForElements(in rect: NSRect) -> [NSCollectionViewLayoutAttributes] {
        return cachedItemAttributes.values.filter { $0.frame.intersects(rect) }
    }
}

extension ListLayout {
    class InvalidationContext: NSCollectionViewLayoutInvalidationContext {
        var preferredLayoutAttributes: NSCollectionViewLayoutAttributes?
    }

    override class var invalidationContextClass: AnyClass { return InvalidationContext.self }

    override func invalidateLayout(with rawContext: NSCollectionViewLayoutInvalidationContext) {
        super.invalidateLayout(with: rawContext)

        // If the collection view's width or the number of items has changed,
        // empty the cache and recalculate the entire layout.
        guard !rawContext.invalidateEverything,
              !rawContext.invalidateDataSourceCounts else {
                print("🍉: Invalidating layout with reload context.")
                cachedItemAttributes.removeAll(keepingCapacity: true)
                return
        }

        guard rawContext.contentSizeAdjustment.width == 0 else {
            print("🍉: Invalidating layout with width adjustment context of \(rawContext.contentSizeAdjustment.width).")
            cachedContentBounds.size.width += rawContext.contentSizeAdjustment.width

            // Recalculate initial layout attributes for each item.
            prepare(sortedItemAttributes: cachedItemAttributes.values.sorted(by: { $0.indexPath! <= $1.indexPath! }))
            return
        }

        // If the invalidation context doesn't specify an item's preferred attributes,
        // empty the cache and recalucalte the entire layout.
        guard let context = rawContext as? InvalidationContext,
              let preferredAttributes = context.preferredLayoutAttributes,
              let indexPath = preferredAttributes.indexPath,
              let originalAttributes = cachedItemAttributes[indexPath] else {
                print("🍉: Invalidating layout with unknown context.")
                cachedItemAttributes.removeAll(keepingCapacity: true)
                return
        }

        print("🍉: Invalidating layout with preferred attributes context.")
        cachedItemAttributes.values.forEach { attributes in
            // Only adjust attributes for the item with preferred attributes,
            // and all items that appear afterwards.
            guard attributes.frame.origin.y >= originalAttributes.frame.origin.y else { return }
            if attributes.indexPath == indexPath {
                // Change the height of the item with preferred attributes.
                attributes.size.height = preferredAttributes.size.height
            } else {
                // Shift all other items' vertical location to account the change in item height.
                attributes.frame.origin.y += context.contentSizeAdjustment.height
            }
        }
    }
}

// MARK: - Preferred Attributes
extension ListLayout {
    override func shouldInvalidateLayout(forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes) -> Bool {
        // Invalidate if the item's preferred size is different from it's original attributes.
        let shouldInvalidateLayout = preferredAttributes.size.height != originalAttributes.size.height
        print("🍇: Should invalidate for preferred attributes? \(shouldInvalidateLayout ? "Yes" : "No").")
        return shouldInvalidateLayout
    }

    // NOTE: This method is never called in Playgrounds, but it should be called immediately after
    //       shouldInvalidateLayout(forPreferredLayoutAttributes:withOriginalAttributes:).
    override func invalidationContext(forPreferredLayoutAttributes preferredAttributes: NSCollectionViewLayoutAttributes, withOriginalAttributes originalAttributes: NSCollectionViewLayoutAttributes) -> NSCollectionViewLayoutInvalidationContext {
        print("🍒: Create invalidation context for preferred attributes.")

        // Get the initial invalidation context.
        let context = super.invalidationContext(forPreferredLayoutAttributes: preferredAttributes, withOriginalAttributes: originalAttributes) as! InvalidationContext

        // Store the preferred attributes within the invalidation context.
        context.preferredLayoutAttributes = preferredAttributes

        // Determine how the item's preferred height affects the collection view's content height.
        context.contentSizeAdjustment.height = preferredAttributes.size.height - originalAttributes.size.height

        // Invalidate the item with preferred attributes and all items the appear afterward.
        let invalidAttributes = cachedItemAttributes.values.filter { attributes in
            attributes.frame.origin.y >= preferredAttributes.frame.origin.y
        }
        let invalidItemIndexPaths = Set(invalidAttributes.compactMap { $0.indexPath })
        context.invalidateItems(at: invalidItemIndexPaths)
        return context
    }
}

// MARK: - Bounds Change
extension ListLayout {
    override func shouldInvalidateLayout(forBoundsChange newBounds: NSRect) -> Bool {
        // We only need to invalidate the layout if the collection view't width changes.
        // Changes in height won't affect the content's height.
        let shouldInvalidateLayout = newBounds.width != cachedContentBounds.width
        print("🍇: Should invalidate for bounds change? \(shouldInvalidateLayout ? "Yes." : "No.")")
        return shouldInvalidateLayout
    }

    override func invalidationContext(forBoundsChange newBounds: NSRect) -> NSCollectionViewLayoutInvalidationContext {
        print("🍒: Create invalidation context for bounds change.")
        let context = super.invalidationContext(forBoundsChange: newBounds)
        context.contentSizeAdjustment.width = newBounds.width - cachedContentBounds.width
        return context
    }
}
