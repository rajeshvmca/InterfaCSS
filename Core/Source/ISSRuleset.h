//
//  ISSRuleset.h
//  Part of InterfaCSS - http://www.github.com/tolo/InterfaCSS
//
//  Copyright (c) Tobias Löfstrand, Leafnode AB.
//  License: MIT - http://www.github.com/tolo/InterfaCSS/blob/master/LICENSE
//

#import <Foundation/Foundation.h>

@class ISSElementStylingProxy, ISSStylingContext, ISSStyleSheetScope, ISSSelectorChain, ISSPropertyValue;

NS_ASSUME_NONNULL_BEGIN


/**
 * Represents a rule set (i.e. a set of selectors/selector chains and a style declarations block) in a stylesheet.
 */
NS_SWIFT_NAME(Ruleset)
@interface ISSRuleset : NSObject

@property (nonatomic, readonly, nullable) ISSSelectorChain* extendedDeclarationSelectorChain;
@property (nonatomic, weak, nullable) ISSRuleset* extendedDeclaration;

@property (nonatomic, readonly) NSArray<ISSSelectorChain*>* selectorChains;
@property (nonatomic, readonly, nullable) NSArray<ISSPropertyValue*>* properties;
@property (nonatomic, readonly) NSString* displayDescription;
@property (nonatomic, readonly) BOOL containsPseudoClassSelector;

@property (nonatomic, readonly) NSUInteger specificity;

@property (nonatomic, weak) ISSStyleSheetScope* scope; // The scope used by the parent stylesheet...

- (instancetype) initWithSelectorChains:(NSArray<ISSSelectorChain*>*)selectorChains andProperties:(nullable NSArray<ISSPropertyValue*>*)properties;
- (instancetype) initWithSelectorChains:(NSArray<ISSSelectorChain*>*)selectorChains andProperties:(nullable NSArray<ISSPropertyValue*>*)properties extendedDeclarationSelectorChain:(nullable ISSSelectorChain*)extendedDeclarationSelectorChain;

- (BOOL) matchesElement:(ISSElementStylingProxy*)elementDetails stylingContext:(ISSStylingContext*)stylingContext;
- (nullable ISSRuleset*) rulesetsMatchingElement:(ISSElementStylingProxy*)elementDetails stylingContext:(ISSStylingContext*)stylingContext;

- (BOOL) containsSelectorChain:(ISSSelectorChain*)selectorChain;

- (NSString*) displayDescription:(BOOL)withProperties;

@end


NS_ASSUME_NONNULL_END
