/**
 * @author v.lugovsky
 * created on 16.12.2015
 */
(function () {
  'use strict';

  angular.module('KongGUI.pages', [
    'ui.router',

    'KongGUI.pages.home',
    'KongGUI.pages.api',
    //'KongGUI.pages.openIDConnectRp',
    'KongGUI.pages.umaRs',
    'KongGUI.pages.login',
    //'KongGUI.pages.umaScript',
    //'KongGUI.pages.oxdWeb'
  ])
      .config(routeConfig);

  /** @ngInject */
  function routeConfig($urlRouterProvider) {
    $urlRouterProvider.otherwise('/home');
  }

})();
