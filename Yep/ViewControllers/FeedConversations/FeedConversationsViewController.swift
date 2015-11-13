//
//  FeedConversationsViewController.swift
//  Yep
//
//  Created by nixzhu on 15/10/12.
//  Copyright © 2015年 Catch Inc. All rights reserved.
//

import UIKit
import RealmSwift

class FeedConversationsViewController: UIViewController {

    @IBOutlet weak var feedConversationsTableView: UITableView!

    var realm: Realm!

    var haveUnreadMessages = false {
        didSet {
            reloadFeedConversationsTableView()
        }
    }

    lazy var feedConversations: Results<Conversation> = {
        //let predicate = NSPredicate(format: "type = %d", ConversationType.Group.rawValue)
        let predicate = NSPredicate(format: "withGroup != nil AND withGroup.groupType = %d", GroupType.Public.rawValue)
        return self.realm.objects(Conversation).filter(predicate).sorted("updatedUnixTime", ascending: false)
        }()

    let feedConversationCellID = "FeedConversationCell"
    let deletedFeedConversationCellID = "DeletedFeedConversationCell"

    deinit {

        NSNotificationCenter.defaultCenter().removeObserver(self)

        println("deinit FeedConversations")
    }

    override func viewDidLoad() {
        super.viewDidLoad()

        title = NSLocalizedString("Feeds", comment: "")

//        navigationItem.backBarButtonItem?.title = NSLocalizedString("Feeds", comment: "")
        
        realm = try! Realm()

        feedConversationsTableView.registerNib(UINib(nibName: feedConversationCellID, bundle: nil), forCellReuseIdentifier: feedConversationCellID)
        feedConversationsTableView.registerNib(UINib(nibName: deletedFeedConversationCellID, bundle: nil), forCellReuseIdentifier: deletedFeedConversationCellID)

        feedConversationsTableView.rowHeight = 80
        feedConversationsTableView.tableFooterView = UIView()
        
        if let gestures = navigationController?.view.gestureRecognizers {
            for recognizer in gestures {
                if recognizer.isKindOfClass(UIScreenEdgePanGestureRecognizer) {
                    feedConversationsTableView.panGestureRecognizer.requireGestureRecognizerToFail(recognizer as! UIScreenEdgePanGestureRecognizer)
                    println("Require UIScreenEdgePanGestureRecognizer to failed")
                    break
                }
            }
        }

        NSNotificationCenter.defaultCenter().addObserver(self, selector: "reloadFeedConversationsTableView", name: YepConfig.Notification.newMessages, object: nil)
    }

    var isFirstAppear = true
    
    override func viewWillAppear(animated: Bool) {
        super.viewWillAppear(animated)

        if !isFirstAppear {
            haveUnreadMessages = countOfUnreadMessagesInRealm(realm, withConversationType: ConversationType.Group) > 0
        }

        isFirstAppear = false
    }

    // MARK: Actions

    func reloadFeedConversationsTableView() {
        dispatch_async(dispatch_get_main_queue()) {
            self.feedConversationsTableView.reloadData()
        }
    }

    // MARK: Navigation

    override func prepareForSegue(segue: UIStoryboardSegue, sender: AnyObject?) {
        if segue.identifier == "showConversation" {
            let vc = segue.destinationViewController as! ConversationViewController
            vc.conversation = sender as! Conversation
        }
    }
}

// MARK: - UITableViewDataSource, UITableViewDelegate

extension FeedConversationsViewController: UITableViewDataSource, UITableViewDelegate {

    func tableView(tableView: UITableView, numberOfRowsInSection section: Int) -> Int {
        return feedConversations.count
    }

    func tableView(tableView: UITableView, cellForRowAtIndexPath indexPath: NSIndexPath) -> UITableViewCell {

        if let conversation = feedConversations[safe: indexPath.row], feed = conversation.withGroup?.withFeed {

            if feed.deleted {
                let cell = tableView.dequeueReusableCellWithIdentifier(deletedFeedConversationCellID) as! DeletedFeedConversationCell
                cell.configureWithConversation(conversation)

                return cell

            } else {
                let cell = tableView.dequeueReusableCellWithIdentifier(feedConversationCellID) as! FeedConversationCell
                cell.configureWithConversation(conversation)
                
                return cell
            }
        }

        let cell = tableView.dequeueReusableCellWithIdentifier(feedConversationCellID) as! FeedConversationCell
        if let conversation = feedConversations[safe: indexPath.row] {
            cell.configureWithConversation(conversation)
        }
        return cell
    }

    func tableView(tableView: UITableView, didSelectRowAtIndexPath indexPath: NSIndexPath) {
        tableView.deselectRowAtIndexPath(indexPath, animated: true)

        if let cell = tableView.cellForRowAtIndexPath(indexPath) as? FeedConversationCell {
            performSegueWithIdentifier("showConversation", sender: cell.conversation)
        }
    }

    // Edit (for Delete)

    func tableView(tableView: UITableView, canEditRowAtIndexPath indexPath: NSIndexPath) -> Bool {

        return true
    }
    
    func tableView(tableView: UITableView, titleForDeleteConfirmationButtonForRowAtIndexPath indexPath: NSIndexPath) -> String? {
        return NSLocalizedString("Unsubscribe", comment: "")
    }

    func tableView(tableView: UITableView, commitEditingStyle editingStyle: UITableViewCellEditingStyle, forRowAtIndexPath indexPath: NSIndexPath) {

        if editingStyle == .Delete {
            
            guard let conversation = feedConversations[safe: indexPath.row] else {
                tableView.setEditing(false, animated: true)
                return
            }

            let doDeleteConversation: () -> Void = {
                
                dispatch_async(dispatch_get_main_queue()) {
                    
                    guard let realm = conversation.realm else {
                        return
                    }
                    
                    deleteConversation(conversation, inRealm: realm)
                    
                    
                    realm.refresh()
                    
                    NSNotificationCenter.defaultCenter().postNotificationName(YepConfig.Notification.changedConversation, object: nil)
                    
                    delay(0.1, work: { () -> Void in
                        tableView.setEditing(false, animated: true)
                        tableView.deleteRowsAtIndexPaths([indexPath], withRowAnimation: .Automatic)
                    })
                    
                }
                
            }
            
            guard let feed = conversation.withGroup?.withFeed, feedCreator = feed.creator else {
                return
            }
            
            let feedID = feed.feedID
            let feedCreatorID = feedCreator.userID
            
            // 若是创建者，再询问是否删除 Feed
            
            if feedCreatorID == YepUserDefaults.userID.value {
                
                YepAlert.confirmOrCancel(title: NSLocalizedString("Delete", comment: ""), message: NSLocalizedString("Also delete this feed?", comment: ""), confirmTitle: NSLocalizedString("Delete", comment: ""), cancelTitle: NSLocalizedString("Not now", comment: ""), inViewController: self, withConfirmAction: {
                    
                    doDeleteConversation()
                    
                    deleteFeedWithFeedID(feedID, failureHandler: nil, completion: {
                        println("deleted feed: \(feedID)")
                    })
                    
                    }, cancelAction: {
                        doDeleteConversation()
                })
                
            } else {
                doDeleteConversation()
            }
        }
    }
}

