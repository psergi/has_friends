# HasFriends Plugin
module Sergi #:nocdoc:
	module HasFriends #:nocdoc:
      
		def self.included(mod)
						mod.extend(ClassMethods)
		end

		# declare the class level helper methods which
		# will load the relevant instance methods
		# defined below when invoked
		module ClassMethods
			def has_friends(options = {})
				class_inheritable_accessor :on_friend_request_callback, 
					:on_friend_approval_callback, 
					:on_friend_denial_callback, 
					:on_friendship_ended_callback
				protected :on_friend_request_callback, 
					:on_friend_approval_callback, 
					:on_friend_denial_callback, 
					:on_friendship_ended_callback

				has_many :friendships, :dependent => :delete_all
				has_many :friend_requests, :class_name =>  'Friendship', :foreign_key => 'friend_id', :conditions => 'accepted = false'
				has_many :pending_friend_requests, :class_name =>  'Friendship', :conditions => 'accepted = false'
				has_many :friends, :through => :friendships, :source => 'friend', :conditions => 'accepted = true'
				has_many :top_friends, :through => :friendships, :source => 'friend', :conditions => 'accepted = true AND top = true'
				include Sergi::HasFriends::InstanceMethods
				extend Sergi::HasFriends::SingletonMethods
			end
		end

		#Adds class methods
		module SingletonMethods
			def on_friend_request(method)
				self.on_friend_request_callback = method
			end
			def on_friend_approval(method)
				self.on_friend_approval_callback = method
			end
			def on_friend_denial(method)
				self.on_friend_denial_callback = method
			end
			def on_friendship_ended(method)
				self.on_friendship_ended_callback = method
			end
		end

		# Adds instance methods.
		module InstanceMethods
			def friends_with?(user)
				return self.friends.include?(user)
			end
			def friendship_status(user)
				friendship = self.friendships.find(:first, :conditions => ['friend_id = ?', user.id])
				if(friendship.nil?)
					friendship = self.friend_requests.find(:first, :conditions => ['user_id = ?', user.id])
					return :requested if(!friendship.nil?)
				end
				return :none if(friendship.nil?)
				return friendship.accepted ? :accepted : :pending
			end
			def accept_friendship(user)
				friendship = friend_requests.find(:first, :conditions => ['user_id = ?', user.id])
				return nil if friendship.nil?
				user_top_friend = user.friends.length < 6
				friendship.update_attributes(:accepted => true, :top => user_top_friend)
				top_friend = self.friends.length < 6
				friendship = Friendship.create(:user => self, :friend => friendship.user, :accepted => true, :top => top_friend)
				fire_callback(self.on_friend_approval_callback, friendship)
				return friendship
			end
			def deny_friendship(user)
				friendship = friend_requests.find(:first, :conditions => ['user_id = ?', user.id])
				return nil if friendship.nil?
				friendship.destroy()
				fire_callback(self.on_friend_denial_callback, friendship)
				return friendship
			end
			def end_friendship(user)
				friendship = self.friendships.find(:first, :conditions => ['friend_id = ?', user.id])
				return nil if friendship.nil?
				Friendship.delete_all("(user_id = #{self.id} AND friend_id = #{user.id}) OR (user_id = #{user.id} AND friend_id = #{self.id})")
				fire_callback(self.on_friendship_ended_callback, friendship)
			end
			def request_friendship(user)
				friendship = Friendship.create(:user => self, :friend => user)
				fire_callback(self.on_friend_request_callback, friendship)
				return friendship
			end
			def add_top_friends(top_friends)
				top_friends = to_id_ary(top_friends)
				self.friendships.update_all("top = 1", "friend_id IN (#{top_friends.join(',')})")
			end
			def remove_top_friends(top_friends)
				top_friends = to_id_ary(top_friends)
				self.friendships.update_all("top = 0", "friend_id IN (#{top_friends.join(',')})")
			end
			def update_top_friends(top_friends)
				top_friends = to_id_ary(top_friends)
				self.friendships.update_all("top = 0")
				return if(top_friends.empty?)
				self.friendships.update_all("top = 1", "friend_id IN (#{top_friends.join(',')})")
			end
			def friend_request_count()
				return Friendship.count(:all, :conditions => ["friend_id = ? AND accepted = ?", self.id, false])
			end
			private 
			def fire_callback(method, param)
				return if(method.nil?)
				method.call(param)
			end
			def to_id_ary(items)
				if(items.is_a?(Array))
					items.map! {|i| i.is_a?(Integer) ? i : i.id}
				else
					items = items.is_a?(Integer) ? [items] : [items.id]
				end
				return items.compact.uniq
			end
		end
	end
end

# reopen ActiveRecord and include all the above to make
# them available to all our models if they want it

ActiveRecord::Base.class_eval do
	include Sergi::HasFriends
end
