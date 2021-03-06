/**
 * This file contains all necessary Angular controller definitions for 'frontend.admin.login-history' module.
 *
 * Note that this file should only contain controllers and nothing else.
 */
(function () {
  'use strict';

  angular.module('frontend.plugins')
    .controller('ApiPluginsController', [
      '_', '$scope', '$stateParams', '$log', '$state', 'ApiService', 'PluginsService',
      '$uibModal', 'DialogService', 'InfoService', '_plugins',
      function controller(_, $scope, $stateParams, $log, $state, ApiService, PluginsService,
                          $uibModal, DialogService, InfoService, _plugins) {


        $scope.plugins = _plugins.data
        $scope.api_id = $stateParams.api_id
        $scope.onAddPlugin = onAddPlugin
        $scope.onEditPlugin = onEditPlugin
        $scope.deletePlugin = deletePlugin
        $scope.updatePlugin = updatePlugin
        $scope.showPluginDetail = showPluginDetail
        $scope.search = ''

        $log.debug("Plugins", $scope.plugins.data)

        /**
         * ----------------------------------------------------------------------
         * Functions
         * ----------------------------------------------------------------------
         */

        function onAddPlugin() {
          $uibModal.open({
            animation: true,
            ariaLabelledBy: 'modal-title',
            ariaDescribedBy: 'modal-body',
            templateUrl: 'js/app/apis/views/add-api-plugin-modal.html',
            size: 'lg',
            controller: 'AddApiPluginModalController',
            resolve: {
              _api: function () {
                return $scope.api
              },
              _plugins: function () {
                return PluginsService.load()
              },
              _info: [
                '$stateParams',
                'InfoService',
                '$log',
                function resolve($stateParams,
                                 InfoService,
                                 $log) {
                  return InfoService.getInfo()
                }
              ]
            }
          });
        }

        function updatePlugin(plugin) {
          PluginsService.update(plugin.id, {
            enabled: plugin.enabled,
            //config : plugin.config
          })
            .then(function (res) {
              $log.debug("updatePlugin", res)
              $scope.plugins.data[$scope.plugins.data.indexOf(plugin)] = res.data;

            }).catch(function (err) {
            $log.error("updatePlugin", err)
          })
        }


        function deletePlugin(plugin) {
          DialogService.prompt(
            "Delete Plugin", "Do you want to delete the selected item?",
            ['CANCEL', 'YES'],
            function accept() {
              PluginsService.delete(plugin.id)
                .then(function (resp) {
                  $scope.plugins.data.splice($scope.plugins.data.indexOf(plugin), 1);
                }).catch(function (err) {
                $log.error(err)
              })
            }, function decline() {
            })
        }

        function onEditPlugin(item) {
          $uibModal.open({
            animation: true,
            ariaLabelledBy: 'modal-title',
            ariaDescribedBy: 'modal-body',
            templateUrl: 'js/app/plugins/modals/edit-plugin-modal.html',
            size: 'lg',
            controller: 'EditPluginController',
            resolve: {
              _plugin: function () {
                return _.cloneDeep(item)
              },
              _schema: function () {
                return PluginsService.schema(item.name)
              }
            }
          });
        }

        function fetchPlugins() {
          PluginsService.load({api_id: $stateParams.api_id})
            .then(function (res) {
              $scope.plugins = res.data
            })
        }

        function showPluginDetail(item) {
          $uibModal.open({
            animation: true,
            templateUrl: 'js/app/plugins/modals/show-plugin-detail-modal.html',
            size: 'lg',
            controller: ['$uibModalInstance', '$scope', 'modelPlugin', ShowPluginController],
            resolve: {
              modelPlugin: function () {
                return item;
              }
            }
          }).result.then(function (result) {
          });
        }

        function ShowPluginController($uibModalInstance, $scope, modelPlugin) {
          $scope.model = angular.copy(modelPlugin);
         // $scope.model.config.protection_document = JSON.parse($scope.model.config.protection_document)
        }

        /**
         * ------------------------------------------------------------
         * Listeners
         * ------------------------------------------------------------
         */
        $scope.$on("plugin.added", function () {
          fetchPlugins()
        })

        $scope.$on("plugin.updated", function (ev, plugin) {
          fetchPlugins()
        })


      }
    ])
  ;
}());
