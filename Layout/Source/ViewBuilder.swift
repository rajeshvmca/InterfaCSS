//
//  ViewBuilder.swift
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT (http://www.github.com/tolo/InterfaCSS/LICENSE)
//

import UIKit


public typealias ViewBuilderCompletionHandler = (_ rootView: UIView?, _ childViewControllers: [UIViewController]?, _ layout: AbstractLayout?, _ parseError: Error?) -> Void

public typealias ViewBuilderLayoutRefreshedObserver = NSObjectProtocol

extension Notification.Name {
  public static let ViewBuilderLayoutRefreshed = Notification.Name(rawValue: "ISSViewBuilderLayoutRefreshedNotification")
}

open class ViewBuilder {

  let logger: Logger

  public static let defaultViewBuilderClass: ViewBuilder.Type = FlexViewBuilder.self
  
  typealias ViewBuilderLayoutRefreshedData = (abstractLayout: AbstractLayout?, parseError: Error?)
  static let ViewBuilderLayoutRefreshedDataKay = "layout"

  public let layoutFileURL: URL
  public let refreshable: Bool
  public weak var defaultFileOwner: AnyObject?
  public let styleSheetName: String
  public let styleSheetGroupName: String
  public let styler: Styler
  
  public private (set) var refresher: RefreshableResource?
  public private (set) var embeddedStyleSheet: StyleSheet?

  public private (set) var lastLayout: AbstractLayout?

  private let dispatchQueue: DispatchQueue

  public required init(layoutFileURL: URL, refreshable: Bool = false, fileOwner: AnyObject? = nil, styler: Styler = StylingManager.shared()) {
    self.layoutFileURL = layoutFileURL
    self.refreshable = refreshable
    self.defaultFileOwner = fileOwner
    self.styleSheetName = layoutFileURL.lastPathComponent
    self.styleSheetGroupName = self.styleSheetName
    self.styler = styler.withScope(StyleSheetScope(styleSheetGroups: [self.styleSheetGroupName]), includeCurrent: true)

    if refreshable {
      if layoutFileURL.isFileURL {
        refresher = RefreshableLocalResource(url: layoutFileURL)
      }
//      else { // TODO: Support remote reloadable layout files?
//        refresher = RefreshableRemoteResource(url: url)
//      }
    }

    self.dispatchQueue = DispatchQueue(label: "ViewBuilder", qos: .background)
    self.logger = Logger("\(type(of:self))(\(layoutFileURL.lastPathComponent))")
  }

  deinit {
    refresher?.endMonitoringResourceModification()
  }


  // MARK: - Main public API
  
  public final func buildView(forceRefresh: Bool = false, fileOwner: AnyObject? = nil, completionHandler: @escaping ViewBuilderCompletionHandler) -> NotificationObserverToken? {
    weak var effectiveFileOwner = fileOwner ?? defaultFileOwner

    var layoutExists = false
    if !forceRefresh {
      layoutExists = buildViewFromLastLayout(fileOwner: effectiveFileOwner, completionHandler: completionHandler) == true
      logger.logTrace(message: "buildViewFromLastLayout - layoutExists: \(layoutExists)")
    }
    if !layoutExists {
      self.dispatchQueue.async { [weak self] in
        var layoutExists = false
        if !forceRefresh {
          DispatchQueue.main.sync {
            self?.logger.logTrace(message: "buildViewFromLastLayout")
            layoutExists = self?.buildViewFromLastLayout(fileOwner: effectiveFileOwner, completionHandler: completionHandler) == true
          }
        }
        if layoutExists { return }

        self?.buildLayout { (parsedLayout, parseError) in
          self?.logger.logTrace(message: "building initial view")
          guard let layout = parsedLayout, let (rootView, childViewControllers) = self?.buildView(fromLayout: layout, fileOwner: effectiveFileOwner) else {
            completionHandler(nil, nil, parsedLayout, parseError)
            return
          }
          completionHandler(rootView, childViewControllers, layout, parseError)
          self?.startRefresherIfSupported()
        }
      }
    }
    
    return addRefreshObserverIfSupported(fileOwner: effectiveFileOwner, completionHandler: completionHandler)
  }
  
  public final func addRefreshObserverIfSupported(fileOwner: AnyObject? = nil, completionHandler: @escaping ViewBuilderCompletionHandler) -> NotificationObserverToken? {
    weak var effectiveFileOwner = fileOwner ?? defaultFileOwner
    if let refresher = refresher, refresher.resourceModificationMonitoringSupported {
      let token = NotificationCenter.default.addObserver(forName: .ViewBuilderLayoutRefreshed, object: self, queue: nil) { [weak self] notification in
        guard let self = self, let (_, _) = notification.userInfo?[ViewBuilder.ViewBuilderLayoutRefreshedDataKay] as? ViewBuilderLayoutRefreshedData else {
          completionHandler(nil, nil, nil, nil) // TODO: Error?
          return
        }
        self.buildViewFromLastLayout(fileOwner: effectiveFileOwner, notifyOnError: true, completionHandler: completionHandler)
      }
      return NotificationObserverToken(token: token)
    } else {
      return nil
    }
  }

  open func createLayoutView(fileOwner: AnyObject? = nil, didLoadCallback: LayoutViewDidLoadCallback? = nil) -> LayoutContainerView {
    return LayoutContainerView(viewBuilder: self, fileOwner: fileOwner, didLoadCallback: didLoadCallback)
  }
  
  open func applyLayout(onView view: UIView) {}
  
  open func calculateLayoutSize(forView view: UIView, fittingSize size: CGSize) -> CGSize {
    return view.sizeThatFits(size)
  }
  
  
  // MARK: - Internal layout/view building methods
  
  @discardableResult
  private final func buildViewFromLastLayout(fileOwner: AnyObject?, notifyOnError: Bool = false, completionHandler: @escaping ViewBuilderCompletionHandler) -> Bool {
    if let lastLayout = lastLayout, let (rootView, childViewControllers) = buildView(fromLayout: lastLayout, fileOwner: fileOwner) {
      completionHandler(rootView, childViewControllers, lastLayout, nil)
      return true
    } else if notifyOnError {
      completionHandler(nil, nil, nil, nil)
    }
    return false
  }
  
  private final func startRefresherIfSupported() {
    // Start refresher, if not started:
    if let refresher = refresher, refresher.resourceModificationMonitoringSupported, !refresher.resourceModificationMonitoringEnabled {
      refresher.startMonitoringResourceModification({ [weak self] resource in
        self?.refreshLayout()
      })
    }
  }
  
  private final func refreshLayout() {
    buildLayout { [unowned self] (parsedLayout, parseError) in
      NotificationCenter.default.post(name: .ViewBuilderLayoutRefreshed, object: self, userInfo: [ViewBuilder.ViewBuilderLayoutRefreshedDataKay: (parsedLayout, parseError)])
    }
  }

  final func buildLayout(completionHandler: @escaping AbstractLayoutCompletionHandler) {
    dispatchQueue.async { [unowned self] in
      do {
        let data = try Data(contentsOf: self.layoutFileURL)
        DispatchQueue.main.sync {
          self.buildLayout(fromData: data, completionHandler: completionHandler)
        }
      } catch (let e) {
        DispatchQueue.main.sync {
          completionHandler(nil, e)
        }
      }
    }
  }
  
  private final func buildLayout(fromData data: Data, completionHandler: AbstractLayoutCompletionHandler) {
    let parser = AbstractViewTreeParser(data: data, styler: styler)
    parser.parse { [weak self] (parsedLayout, parseError) in
      if let parsedLayout = parsedLayout {
        self?.lastLayout = parsedLayout
      }
      if let parseError = parseError {
        logger.logDebug(message: "Error parsing: \(parseError)")
      }
      if let self = self, let styleSheetContent = parsedLayout?.layoutStyle {
        if let styleSheet = embeddedStyleSheet {
          styler.styleSheetManager.unloadStyleSheet(styleSheet)
        }
        embeddedStyleSheet = StyleSheet(styleSheetURL: layoutFileURL, name: self.styleSheetName, group: self.styleSheetGroupName, content: styleSheetContent)
        setDefaultStyleSheetVariables()
        styler.styleSheetManager.registerStyleSheet(embeddedStyleSheet!)
      }
        
      completionHandler(parsedLayout, parseError)
    }
  }
  
  private func setDefaultStyleSheetVariables() {
    var safeAreaInsets: UIEdgeInsets = .zero
    var layoutMargins: UIEdgeInsets = .zero
    if let fileOwner = defaultFileOwner as? UIViewController, let rootView = fileOwner.viewIfLoaded {
      safeAreaInsets = rootView.safeAreaInsets
      layoutMargins = rootView.layoutMargins
    }
    
    embeddedStyleSheet?.content?.setValue("\(safeAreaInsets.top)", forStyleSheetVariableWithName: "safeAreaInsets-top")
    embeddedStyleSheet?.content?.setValue("\(safeAreaInsets.left)", forStyleSheetVariableWithName: "safeAreaInsets-left")
    embeddedStyleSheet?.content?.setValue("\(safeAreaInsets.bottom)", forStyleSheetVariableWithName: "safeAreaInsets-bottom")
    embeddedStyleSheet?.content?.setValue("\(safeAreaInsets.right)", forStyleSheetVariableWithName: "safeAreaInsets-right")
    
    embeddedStyleSheet?.content?.setValue("\(layoutMargins.top)", forStyleSheetVariableWithName: "layoutMargins-top")
    embeddedStyleSheet?.content?.setValue("\(layoutMargins.left)", forStyleSheetVariableWithName: "layoutMargins-left")
    embeddedStyleSheet?.content?.setValue("\(layoutMargins.bottom)", forStyleSheetVariableWithName: "layoutMargins-bottom")
    embeddedStyleSheet?.content?.setValue("\(layoutMargins.right)", forStyleSheetVariableWithName: "layoutMargins-right")
  }

  private final func buildView(fromLayout layout: AbstractLayout, fileOwner: AnyObject?) -> (UIView, [UIViewController])? {
    guard let (rootView, childViewControllers) = createViewTree(withRootNode: layout.rootNode, fileOwner: fileOwner) else {
      return nil
    }
    if let title = layout.title, let fileOwner = fileOwner as? UIViewController {
      fileOwner.title = title
      fileOwner.navigationItem.title = title
    }
    styler.applyStyling(rootView)
    return (rootView, childViewControllers)
  }


  // MARK: - Support methods (for subclasses)

  open func createViewTree(withRootNode root: AbstractViewTreeNode, fileOwner: AnyObject? = nil) -> (UIView, [UIViewController])? {
    var childViewControllers: [UIViewController] = []
    let rootView = root.visitAbstractViewTree() { (node, parentNode, parentView) in
      guard let viewObject = instantiateViewObject(for: node, parentView: parentView, fileOwner: fileOwner), node.addToViewHierarchy else {
        return nil
      }
      guard let parentView = parentView as? UIView else {
        return viewObject
      }
      if let childViewController = viewObject as? UIViewController, let parentViewController = fileOwner as? UIViewController {
        parentViewController.addChild(childViewController)
        childViewController.view.frame = parentView.bounds
        addViewObject(childViewController.view, toParentView: parentView, fileOwner: fileOwner)
        childViewControllers.append(childViewController)
        return childViewController.view
      } else {
        addViewObject(viewObject, toParentView: parentView, fileOwner: fileOwner)
        return viewObject
      }
    } as? UIView

    if let rootView = rootView {
      return (rootView, childViewControllers)
    } else {
      return nil
    }
  }

  open func addViewObject(_ viewObject: AnyObject, toParentView parentView: UIView, fileOwner: AnyObject?) {
    if let view = viewObject as? UIView {
      parentView.addSubview(view)
    }
  }

  open func instantiateViewObject(for node: AbstractViewTreeNode, parentView: AnyObject?, fileOwner: AnyObject?) -> AnyObject? {
    return node.elementType.createElement(forNode: node, parentView: parentView, viewBuilder: self, fileOwner: fileOwner)
  }
}
