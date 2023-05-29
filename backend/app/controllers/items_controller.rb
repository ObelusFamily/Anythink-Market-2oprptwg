# frozen_string_literal: true
require_relative "../../lib/event"
# require "openai"
require 'uri'
require 'net/http'

include Event

class ItemsController < ApplicationController
  before_action :authenticate_user!, except: %i[index show]

  def index
    @items = Item.includes(:tags)

    @items = @items.tagged_with(params[:tag]) if params[:tag].present?
    @items = @items.sellered_by(params[:seller]) if params[:seller].present?
    @items = @items.favorited_by(params[:favorited]) if params[:favorited].present?

    @items_count = @items.count

    @items = @items.order(created_at: :desc).offset(params[:offset] || 0).limit(params[:limit] || 100)

    render json: {
      items: @items.map { |item|
        {
          title: item.title,
          slug: item.slug,
          description: item.description,
          image: item.image,
          tagList: item.tags.map(&:name),
          createdAt: item.created_at,
          updatedAt: item.updated_at,
          seller: {
            username: item.user.username,
            bio: item.user.bio,
            image: item.user.image || 'https://static.productionready.io/images/smiley-cyrus.jpg',
            following: signed_in? ? current_user.following?(item.user) : false,
          },
          favorited: signed_in? ? current_user.favorited?(item) : false,
          favoritesCount: item.favorites_count || 0
        }
      },
      items_count: @items_count
    }
  end

  def feed
    @items = Item.includes(:user).where(user: current_user.following_users)

    @items_count = @items.count

    @items = @items.order(created_at: :asc).offset(params[:offset] || 0).limit(params[:limit] || 20)

    render :index
  end

  def create
    @item = Item.new(item_params)
    @item.user = current_user

    if @item.image.exists? == false 
      @item.image = create_image(:title, :description)
    end  

    if @item.save
      sendEvent("item_created", { item: item_params })
      render :show
    else
      render json: { errors: @item.errors }, status: :unprocessable_entity
    end
  end

  def show
    @item = Item.find_by!(slug: params[:slug])
  end

  def update
    @item = Item.find_by!(slug: params[:slug])

    if @item.user_id == @current_user_id
      @item.update(item_params)

      render :show
    else
      render json: { errors: { item: ['not owned by user'] } }, status: :forbidden
    end
  end

  def destroy
    @item = Item.find_by!(slug: params[:slug])

    if @item.user_id == @current_user_id
      @item.destroy

      render json: {}
    else
      render json: { errors: { item: ['not owned by user'] } }, status: :forbidden
    end
  end

  private

  def item_params
    params.require(:item).permit(:title, :description, :image, tag_list: [])
  end

  def create_image(title, description)
    # Authorization: Bearer OPENAI_API_KEY
    # curl https://api.openai.com/v1/images/generations \
    # -H "Content-Type: application/json" \
    # -H "Authorization: Bearer $OPENAI_API_KEY" \
    # -d '{
    #   "prompt": "A cute baby sea otter",
    #   "n": 2,
    #   "size": "1024x1024"
    # }'

    # uri = URI('https://jsonplaceholder.typicode.com/posts')
    # res = Net::HTTP.post_form(uri, 'title' => 'foo', 'body' => 'bar', 'userID' => 1)
    # puts res.body  if res.is_a?(Net::HTTPSuccess)

    url = "https://api.openai.com/v1/images/generations" 
    header = {
      Content-Type: "application/json", 
      Authorization: "Bearer #{OPENAI_API_KEY}"
      Parameters: {
        "prompt": "#{title} #{description}",
        "n": 1,
        "size": "256x256"
      }
    }
    uri = URI(url)
    res = Net::HTTP.post_form(uri, header)
    res.body  if res.is_a?(Net::HTTPSuccess)

  end 
end
