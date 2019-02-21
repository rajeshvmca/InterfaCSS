//
//  LayoutTableViewCell.swift
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

import UIKit

/**
 * LayoutTableViewCell
 */
open class LayoutTableViewCell: UITableViewCell {

  public var layoutContainerView: LayoutContainerView!

  override open func layoutSubviews() {
    layoutContainerView?.frame = contentView.bounds
    super.layoutSubviews()
  }


  // MARK: - LayoutTableViewCell main API
  
  func configureLayout(withViewBuilder viewBuilder: ViewBuilder, didLoadCallback: LayoutViewDidLoadCallback? = nil) {
    guard layoutContainerView == nil else {
      return
    }
    layoutContainerView = viewBuilder.createLayoutView(fileOwner: self) { [weak self] (container, view) in
      didLoadCallback?(container, view)
      self?.layout(view: view, didLoadIn: container)
    }
    layoutContainerView.translatesAutoresizingMaskIntoConstraints = false
    layoutContainerView.frame = contentView.frame
    contentView.addSubview(layoutContainerView)
  }

  public func updateLayout() {
    layoutContainerView.updateLayout()
  }

  open func calculateContentHeightThatFits(_ size: CGSize) -> CGFloat {
    return layoutContainerView.sizeThatFits(size).height
  }
  
  open override func setSelected(_ selected: Bool, animated: Bool) {
    super.setSelected(selected, animated: animated)
    guard let layoutContainerView = layoutContainerView else { return }
    layoutContainerView.styler.applyStyling(self)
  }


  // MARK: - LayoutTableViewCell sub class interface

  open func layout(view: UIView, didLoadIn containerView: LayoutContainerView) {
    populateCell()
  }

  open func populateCell() {}
}